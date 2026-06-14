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
        private var continuation: CheckedContinuation<RESPValue, Error>?

        init(_ continuation: CheckedContinuation<RESPValue, Error>) {
            self.continuation = continuation
        }

        func complete(_ result: Result<RESPValue, Error>) {
            let continuation: CheckedContinuation<RESPValue, Error>?
            lock.lock()
            continuation = self.continuation
            self.continuation = nil
            lock.unlock()

            guard let continuation else { return }

            switch result {
            case .success(let value):
                continuation.resume(returning: value)
            case .failure(let error):
                continuation.resume(throwing: error)
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
        preferredProtocolVersion: RESPProtocolVersion = .resp2
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
                                // Perform RESP3 handshake if preferred
                                if self?.preferredProtocolVersion == .resp3 {
                                    try await self?.performResp3Handshake()
                                }

                                // Authenticate if credentials are provided.
                                let user = self?.username ?? ""
                                let pw = self?.password ?? ""
                                if !user.isEmpty || !pw.isEmpty {
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

    // MARK: - RESP3 Handshake

    private func performResp3Handshake() async throws {
        // Send HELLO 3 command to negotiate RESP3
        // HELLO 3 [AUTH username password] [SETNAME clientname]
        let result = try await sendHelloCommand()

        switch result {
        case .map(let entries):
            // RESP3 HELLO response is a map with server info
            serverCapabilities = entries.reduce(into: [:]) { dict, entry in
                if let keyString = entry.key.string {
                    dict[keyString] = entry.value
                }
            }
            negotiatedProtocolVersion = .resp3

        case .error(let message):
            // HELLO command failed, fall back to RESP2
            AppLogger.debug("RESP3 handshake failed: \(message), falling back to RESP2")
            negotiatedProtocolVersion = .resp2

        default:
            // Unexpected response, fall back to RESP2
            AppLogger.debug("Unexpected HELLO response, falling back to RESP2")
            negotiatedProtocolVersion = .resp2
        }
    }

    private func sendHelloCommand() async throws -> RESPValue {
        // Build and send HELLO 3 command
        let data = buildHelloCommand()

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

    private func buildHelloCommand() -> Data {
        // Build HELLO 3 command as RESP2 array
        var data = Data()
        data.append(contentsOf: "*2\r\n".utf8)
        // First element: $5\r\nHELLO\r\n
        data.append(contentsOf: "$5\r\n".utf8)
        data.append(contentsOf: "HELLO\r\n".utf8)
        // Second element: $1\r\n3\r\n
        data.append(contentsOf: "$1\r\n".utf8)
        data.append(contentsOf: "3\r\n".utf8)
        return data
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
