import Combine
import Foundation
import Network

class RedisClient: ObservableObject, @unchecked Sendable {
    private final class ConnectContinuationState: @unchecked Sendable {
        private let lock = NSLock()
        private var didResume = false

        func tryMarkResumed() -> Bool {
            lock.lock()
            defer { lock.unlock() }

            guard !didResume else { return false }
            didResume = true
            return true
        }
    }

    private final class PendingCommand: @unchecked Sendable {
        private let lock = NSLock()
        private var completion: (@Sendable (Result<RESPValue, Error>) -> Void)?

        init(_ continuation: CheckedContinuation<RESPValue, Error>) {
            completion = { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        init(completion: @escaping @Sendable (Result<RESPValue, Error>) -> Void) {
            self.completion = completion
        }

        func complete(_ result: Result<RESPValue, Error>) {
            let completion: (@Sendable (Result<RESPValue, Error>) -> Void)?
            lock.lock()
            completion = self.completion
            self.completion = nil
            lock.unlock()

            completion?(result)
        }
    }

    private final class PendingPipeline: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [RESPValue?]
        private var remainingCount: Int
        private var continuation: CheckedContinuation<[RESPValue], Error>?

        init(count: Int, continuation: CheckedContinuation<[RESPValue], Error>) {
            results = Array(repeating: nil, count: count)
            remainingCount = count
            self.continuation = continuation
        }

        func complete(index: Int, with result: Result<RESPValue, Error>) {
            var continuationToResume: CheckedContinuation<[RESPValue], Error>?
            var resultToResume: Result<[RESPValue], Error>?

            lock.lock()
            if let storedContinuation = continuation {
                switch result {
                case .success(let value):
                    results[index] = value
                    remainingCount -= 1
                    if remainingCount == 0 {
                        var values: [RESPValue] = []
                        values.reserveCapacity(results.count)
                        var missingResponse = false
                        for response in results {
                            guard let response else {
                                missingResponse = true
                                break
                            }
                            values.append(response)
                        }

                        continuationToResume = storedContinuation
                        resultToResume =
                            missingResponse
                            ? .failure(RedisError.parseError("Missing Redis pipeline response"))
                            : .success(values)
                        continuation = nil
                    }
                case .failure(let error):
                    continuationToResume = storedContinuation
                    resultToResume = .failure(error)
                    continuation = nil
                }
            }
            lock.unlock()

            guard let continuationToResume, let resultToResume else { return }
            switch resultToResume {
            case .success(let values):
                continuationToResume.resume(returning: values)
            case .failure(let error):
                continuationToResume.resume(throwing: error)
            }
        }
    }

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "redis.client.queue")
    private let queueKey = DispatchSpecificKey<Bool>()
    private var pendingCompletions: [PendingCommand] = []
    private var parser = RESPParser()

    @Published var isConnected = false
    @Published var lastError: String?

    let host: String
    let port: UInt16
    let username: String?
    let password: String?
    let tlsEnabled: Bool
    let verifyServerCertificate: Bool
    let caCertificatePath: String
    let clientCertificatePath: String
    let clientKeyPath: String
    let preferredProtocolVersion: RESPProtocolVersion

    private(set) var negotiatedProtocolVersion: RESPProtocolVersion = .resp2
    private(set) var serverCapabilities: [String: RESPValue] = [:]
    private var protocolFallbackReason: String?

    init(
        host: String,
        port: UInt16,
        username: String? = nil,
        password: String? = nil,
        tlsEnabled: Bool = false,
        verifyServerCertificate: Bool = true,
        caCertificatePath: String = "",
        clientCertificatePath: String = "",
        clientKeyPath: String = "",
        preferredProtocolVersion: RESPProtocolVersion = .resp3
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.tlsEnabled = tlsEnabled
        self.verifyServerCertificate = verifyServerCertificate
        self.caCertificatePath = caCertificatePath
        self.clientCertificatePath = clientCertificatePath
        self.clientKeyPath = clientKeyPath
        self.preferredProtocolVersion = preferredProtocolVersion
        queue.setSpecific(key: queueKey, value: true)
    }

    func connect() async throws {
        negotiatedProtocolVersion = .resp2
        serverCapabilities = [:]
        protocolFallbackReason = nil

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let continuationState = ConnectContinuationState()

            let params: NWParameters
            if tlsEnabled {
                let tlsOptions = NWProtocolTLS.Options()

                if !caCertificatePath.isEmpty || !clientCertificatePath.isEmpty || !clientKeyPath.isEmpty {
                    sec_protocol_options_set_verify_block(
                        tlsOptions.securityProtocolOptions,
                        { [caCertificatePath = self.caCertificatePath] _, trust, completionHandler in
                            // swiftlint:disable:next force_cast
                            let secTrust = trust as! SecTrust

                            if !caCertificatePath.isEmpty {
                                let url = URL(fileURLWithPath: caCertificatePath)
                                if let caData = try? Data(contentsOf: url) {
                                    let caCert = SecCertificateCreateWithData(nil, caData as CFData)
                                    if let caCert {
                                        SecTrustSetAnchorCertificates(secTrust, [caCert] as CFArray)
                                        SecTrustSetAnchorCertificatesOnly(secTrust, false)
                                    }
                                }
                            }

                            var error: CFError?
                            let isValid = SecTrustEvaluateWithError(secTrust, &error)
                            completionHandler(isValid)
                        },
                        .main
                    )
                } else if !verifyServerCertificate {
                    sec_protocol_options_set_verify_block(
                        tlsOptions.securityProtocolOptions,
                        { _, _, completionHandler in
                            completionHandler(true)
                        },
                        .main
                    )
                }

                if !clientCertificatePath.isEmpty && !clientKeyPath.isEmpty {
                    let certURL = URL(fileURLWithPath: clientCertificatePath)
                    if let certData = try? Data(contentsOf: certURL) {
                        let cert = SecCertificateCreateWithData(nil, certData as CFData)
                        if let cert {
                            var identity: SecIdentity?
                            let status = SecIdentityCreateWithCertificate(
                                nil,
                                cert,
                                &identity
                            )
                            if status == errSecSuccess, let identity {
                                let secIdentity = sec_identity_create(identity)
                                if let secIdentity {
                                    sec_protocol_options_set_local_identity(
                                        tlsOptions.securityProtocolOptions,
                                        secIdentity
                                    )
                                }
                            }
                        }
                    }
                }

                sec_protocol_options_set_tls_server_name(
                    tlsOptions.securityProtocolOptions,
                    host
                )

                params = NWParameters(tls: tlsOptions, tcp: .init())
            } else {
                params = NWParameters.tcp
            }
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(throwing: RedisError.commandError("Invalid Redis port: \(port)"))
                return
            }

            connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: params
            )

            connection?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isConnected = true
                        self?.startReceiving()

                        Task {
                            do {
                                var authenticatedByHello = false
                                if self?.preferredProtocolVersion == .resp3 {
                                    authenticatedByHello = try await self?.performResp3Handshake() ?? false
                                }

                                // Authenticate if credentials are provided.
                                let user = self?.username ?? ""
                                let pw = self?.password ?? ""
                                if (!user.isEmpty || !pw.isEmpty) && !authenticatedByHello {
                                    let result: RESPValue
                                    if !user.isEmpty {
                                        result = try await self?.send("AUTH", user, pw) ?? .null
                                    } else {
                                        result = try await self?.send("AUTH", pw) ?? .null
                                    }
                                    if case .error(let msg) = result {
                                        self?.lastError = msg
                                        throw RedisError.commandError(msg)
                                    }
                                }
                                self?.logNegotiatedProtocol(authenticatedByHello: authenticatedByHello)

                                if continuationState.tryMarkResumed() {
                                    continuation.resume()
                                }
                            } catch {
                                self?.lastError = error.localizedDescription
                                if continuationState.tryMarkResumed() {
                                    continuation.resume(throwing: error)
                                }
                            }
                        }
                    case .failed(let error):
                        self?.isConnected = false
                        self?.lastError = error.localizedDescription
                        if continuationState.tryMarkResumed() {
                            continuation.resume(throwing: error)
                        }
                    case .waiting(let error):
                        self?.lastError = error.localizedDescription
                    case .cancelled:
                        self?.isConnected = false
                        if continuationState.tryMarkResumed() {
                            continuation.resume(throwing: RedisError.notConnected)
                        }
                    default:
                        break
                    }
                }
            }

            connection?.start(queue: queue)
        }
    }

    func disconnect() {
        disconnect(publishState: true)
    }

    private func disconnect(publishState: Bool) {
        let disconnectAction = {
            self.cancelConnectionOnQueue()
        }

        if DispatchQueue.getSpecific(key: queueKey) == true {
            disconnectAction()
        } else {
            queue.sync(execute: disconnectAction)
        }

        guard publishState else { return }
        updateConnectionState(isConnected: false)
    }

    private func updateConnectionState(isConnected: Bool, lastError: String? = nil) {
        if Thread.isMainThread {
            self.isConnected = isConnected
            if let lastError {
                self.lastError = lastError
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.isConnected = isConnected
            if let lastError {
                self?.lastError = lastError
            }
        }
    }

    private func removePendingCompletion(_ completion: PendingCommand) {
        if let index = pendingCompletions.firstIndex(where: { $0 === completion }) {
            pendingCompletions.remove(at: index)
        }
    }

    private func failPendingCompletion(_ completion: PendingCommand, with error: Error) {
        removePendingCompletion(completion)
        completion.complete(.failure(error))
    }

    private func receiveLoop() {
        queue.async {
            self.connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.queue.async {
                        self.parser.append(data)
                        self.processBuffer()
                    }
                }
                if error == nil && !isComplete {
                    self.receiveLoop()
                } else {
                    self.queue.async {
                        self.completePendingCommands(with: error ?? RedisError.notConnected)
                        self.parser = RESPParser()
                    }
                    self.updateConnectionState(isConnected: false, lastError: error?.localizedDescription)
                }
            }
        }
    }

    private func completePendingCommands(with error: Error) {
        let pendingCompletions = pendingCompletions
        self.pendingCompletions.removeAll()
        for completion in pendingCompletions {
            completion.complete(.failure(error))
        }
    }

    private func cancelConnectionOnQueue() {
        connection?.cancel()
        connection = nil
        completePendingCommands(with: RedisError.notConnected)
        parser = RESPParser()
    }

    private func startReceiving() {
        receiveLoop()
    }

    private func processBuffer() {
        while let value = parser.parse() {
            if let completion = pendingCompletions.first {
                pendingCompletions.removeFirst()
                completion.complete(.success(value))
            }
        }
    }

    func send(_ args: String...) async throws -> RESPValue {
        try await send(args)
    }

    func send(_ args: [String]) async throws -> RESPValue {
        guard isConnected else {
            throw RedisError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Use negotiated protocol version for encoding
            let data = RESPEncoder.encode(args, version: negotiatedProtocolVersion)
            let pendingCompletion = PendingCommand(continuation)

            self.queue.async {
                guard let connection = self.connection else {
                    pendingCompletion.complete(.failure(RedisError.notConnected))
                    return
                }

                self.pendingCompletions.append(pendingCompletion)

                connection.send(
                    content: data,
                    completion: .contentProcessed { error in
                        if let error = error {
                            self.queue.async {
                                self.failPendingCompletion(pendingCompletion, with: error)
                            }
                        }
                    })
            }
        }
    }

    func sendPipeline(_ commands: [[String]]) async throws -> [RESPValue] {
        guard isConnected else {
            throw RedisError.notConnected
        }
        guard !commands.isEmpty else { return [] }
        guard commands.allSatisfy({ !$0.isEmpty }) else {
            throw RedisError.commandError("Redis command is empty")
        }

        return try await withCheckedThrowingContinuation { continuation in
            var data = Data()
            for command in commands {
                data.append(RESPEncoder.encode(command, version: negotiatedProtocolVersion))
            }

            let pipeline = PendingPipeline(count: commands.count, continuation: continuation)
            let pendingCommands = commands.indices.map { index in
                PendingCommand { result in
                    pipeline.complete(index: index, with: result)
                }
            }

            self.queue.async {
                guard let connection = self.connection else {
                    for pendingCommand in pendingCommands {
                        pendingCommand.complete(.failure(RedisError.notConnected))
                    }
                    return
                }

                self.pendingCompletions.append(contentsOf: pendingCommands)

                connection.send(
                    content: data,
                    completion: .contentProcessed { error in
                        if let error = error {
                            self.queue.async {
                                for pendingCommand in pendingCommands {
                                    self.failPendingCompletion(pendingCommand, with: error)
                                }
                            }
                        }
                    })
            }
        }
    }

    // MARK: - RESP3 Handshake

    @discardableResult
    private func performResp3Handshake() async throws -> Bool {
        let result = try await sendHelloCommand(protocolVersion: .resp3, includeAuthentication: helloCommandIncludesAuthentication)
        let helloIncludesAuthentication = helloCommandIncludesAuthentication

        switch result {
        case .map(let entries):
            // RESP3 HELLO response is a map with server info
            serverCapabilities = normalizedHelloCapabilities(from: entries)
            negotiatedProtocolVersion = .resp3
            if let fallbackReason = resp3FallbackReason(serverVersion: serverVersion) {
                try await downgradeToResp2(serverVersion: serverVersion, fallbackReason: fallbackReason)
            }
            return helloIncludesAuthentication

        case .error(let message):
            // HELLO command failed, fall back to RESP2
            AppLogger.debug("RESP3 handshake failed: \(message), falling back to RESP2")
            negotiatedProtocolVersion = .resp2
            protocolFallbackReason = "resp3_handshake_failed"
            return false

        default:
            // Unexpected response, fall back to RESP2
            AppLogger.debug("Unexpected HELLO response, falling back to RESP2")
            negotiatedProtocolVersion = .resp2
            protocolFallbackReason = "unexpected_hello_response"
            return false
        }
    }

    private func sendHelloCommand(
        protocolVersion: RESPProtocolVersion,
        includeAuthentication: Bool
    ) async throws -> RESPValue {
        let data = RESPEncoder.encode(
            helloCommandArguments(protocolVersion: protocolVersion, includeAuthentication: includeAuthentication),
            version: .resp2
        )

        return try await withCheckedThrowingContinuation { continuation in
            let pendingCompletion = PendingCommand(continuation)

            self.queue.async {
                guard let connection = self.connection else {
                    pendingCompletion.complete(.failure(RedisError.notConnected))
                    return
                }

                self.pendingCompletions.append(pendingCompletion)

                connection.send(
                    content: data,
                    completion: .contentProcessed { error in
                        if let error = error {
                            self.queue.async {
                                self.failPendingCompletion(pendingCompletion, with: error)
                            }
                        }
                    })
            }
        }
    }

    private var helloCommandIncludesAuthentication: Bool {
        let user = username ?? ""
        let pw = password ?? ""
        return !user.isEmpty || !pw.isEmpty
    }

    private func helloCommandArguments(
        protocolVersion: RESPProtocolVersion,
        includeAuthentication: Bool
    ) -> [String] {
        var args = ["HELLO", protocolVersion.helloArgument]
        guard includeAuthentication else { return args }

        let user = username ?? ""
        let pw = password ?? ""
        args.append(contentsOf: ["AUTH", user.isEmpty ? "default" : user, pw])
        return args
    }

    private var serverVersion: String? {
        serverCapabilities["version"]?.string ?? serverCapabilities["redis_version"]?.string
    }

    private func normalizedHelloCapabilities(from entries: [RESPMapEntry]) -> [String: RESPValue] {
        normalizedHelloCapabilities(from: entries.map { (key: $0.key, value: $0.value) })
    }

    private func normalizedHelloCapabilities(from pairs: [(key: RESPValue, value: RESPValue)]) -> [String: RESPValue] {
        pairs.reduce(into: [:]) { dict, pair in
            guard let keyString = pair.key.string?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                !keyString.isEmpty
            else {
                return
            }
            dict[keyString] = pair.value
        }
    }

    private func resp3FallbackReason(serverVersion: String?) -> String? {
        guard let serverVersion else {
            return "missing_server_version_after_hello3"
        }

        guard let majorVersion = serverMajorVersion(from: serverVersion) else {
            return "unparseable_server_version_after_hello3"
        }

        guard majorVersion >= 7 else {
            return "redis_resp3_experimental_before_7"
        }

        return nil
    }

    private func serverMajorVersion(from serverVersion: String) -> Int? {
        let majorComponent = serverVersion.split(separator: ".", maxSplits: 1).first ?? Substring(serverVersion)
        let majorDigits = majorComponent.prefix { $0.isNumber }
        return Int(majorDigits)
    }

    private func downgradeToResp2(serverVersion: String?, fallbackReason: String) async throws {
        let result = try await sendHelloCommand(protocolVersion: .resp2, includeAuthentication: false)
        if case .error(let message) = result {
            let serverDescription = serverVersion.map { "Redis \($0)" } ?? "Redis server"
            throw RedisError.commandError("Unable to use RESP2 for \(serverDescription): \(message)")
        }

        serverCapabilities.merge(normalizedHelloCapabilities(from: result.keyValuePairs)) { _, new in new }
        negotiatedProtocolVersion = .resp2
        serverCapabilities["proto"] = .integer(2)
        protocolFallbackReason = fallbackReason
    }

    private func logNegotiatedProtocol(authenticatedByHello: Bool) {
        var fields = [
            "auth_via_hello": "\(authenticatedByHello)",
            "host": host,
            "negotiated_protocol": negotiatedProtocolVersion.logName,
            "port": "\(port)",
            "preferred_protocol": preferredProtocolVersion.logName,
            "tls_enabled": "\(tlsEnabled)",
        ]
        if let serverVersion {
            fields["server_version"] = serverVersion
        }
        if serverVersion == nil, !serverCapabilities.isEmpty {
            fields["hello_keys"] = serverCapabilities.keys.sorted().joined(separator: ",")
        }
        if let serverProtocol = serverCapabilities["proto"]?.intValue {
            fields["server_protocol"] = "\(serverProtocol)"
        }
        if let protocolFallbackReason {
            fields["fallback_reason"] = protocolFallbackReason
        }

        AppLogger.info(
            "redis protocol negotiated",
            category: "Connection",
            fields: fields
        )
    }

    deinit {
        disconnect(publishState: false)
    }
}

enum RedisError: LocalizedError {
    case notConnected
    case parseError(String)
    case commandError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to Redis server"
        case .parseError(let msg): return "Parse error: \(msg)"
        case .commandError(let msg): return "Command error: \(msg)"
        }
    }
}
