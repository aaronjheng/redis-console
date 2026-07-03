import Foundation
import Network
import Synchronization

final class RedisClient: Sendable {
    private final class ConnectContinuationState: Sendable {
        private struct State: Sendable {
            var continuation: CheckedContinuation<Void, Error>?
            var result: Result<Void, Error>?
        }

        private let state = Mutex(State())

        var isCompleted: Bool {
            state.withLock { $0.result != nil }
        }

        func setContinuation(_ continuation: CheckedContinuation<Void, Error>) {
            let result = state.withLock { state -> Result<Void, Error>? in
                if let result = state.result {
                    return result
                }
                state.continuation = continuation
                return nil
            }

            if let result {
                resume(continuation, with: result)
            }
        }

        @discardableResult
        func complete(_ result: Result<Void, Error>) -> Bool {
            let (continuation, didComplete) = state.withLock { state -> (CheckedContinuation<Void, Error>?, Bool) in
                guard state.result == nil else { return (nil, false) }
                state.result = result
                let continuation = state.continuation
                state.continuation = nil
                return (continuation, true)
            }

            if let continuation {
                resume(continuation, with: result)
            }
            return didComplete
        }

        private func resume(_ continuation: CheckedContinuation<Void, Error>, with result: Result<Void, Error>) {
            switch result {
            case .success:
                continuation.resume()
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    private final class PendingCommand: Sendable {
        private typealias CommandCompletion = @Sendable (Result<RESPValue, Error>) -> Void

        private struct State: Sendable {
            var completion: CommandCompletion?
            var result: Result<RESPValue, Error>?
            var isQueuedForResponse = false
        }

        let id = UUID()
        private let state = Mutex(State())

        var isCompleted: Bool {
            state.withLock { $0.result != nil }
        }

        init(_ continuation: CheckedContinuation<RESPValue, Error>) {
            setContinuation(continuation)
        }

        init() {}

        func setContinuation(_ continuation: CheckedContinuation<RESPValue, Error>) {
            setCompletion { result in
                Self.resume(continuation, with: result)
            }
        }

        init(completion: @escaping @Sendable (Result<RESPValue, Error>) -> Void) {
            setCompletion(completion)
        }

        func reserveResponseSlot() -> Bool {
            state.withLock {
                guard $0.result == nil else { return false }
                $0.isQueuedForResponse = true
                return true
            }
        }

        func complete(_ result: Result<RESPValue, Error>) {
            let completion: (@Sendable (Result<RESPValue, Error>) -> Void)? = state.withLock {
                guard $0.result == nil else { return nil }
                $0.result = result
                let completion = $0.completion
                $0.completion = nil
                return completion
            }
            completion?(result)
        }

        func cancel() -> Bool {
            let (completion, shouldRemoveFromQueue) = state.withLock { state -> (CommandCompletion?, Bool) in
                let shouldRemoveFromQueue = !state.isQueuedForResponse
                guard state.result == nil else { return (nil, shouldRemoveFromQueue) }
                state.result = Result<RESPValue, Error>.failure(CancellationError())
                let completion = state.completion
                state.completion = nil
                return (completion, shouldRemoveFromQueue)
            }
            completion?(Result<RESPValue, Error>.failure(CancellationError()))
            return shouldRemoveFromQueue
        }

        private func setCompletion(_ completion: @escaping CommandCompletion) {
            let result = state.withLock { state -> Result<RESPValue, Error>? in
                if let result = state.result {
                    return result
                }
                state.completion = completion
                return nil
            }

            if let result {
                completion(result)
            }
        }

        private static func resume(
            _ continuation: CheckedContinuation<RESPValue, Error>,
            with result: Result<RESPValue, Error>
        ) {
            switch result {
            case .success(let value):
                continuation.resume(returning: value)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    private final class PendingCommandBatch: Sendable {
        private struct State: Sendable {
            var isCancelled = false
            var commands: [PendingCommand] = []
        }

        private let state = Mutex(State())

        func setCommands(_ commands: [PendingCommand]) -> Bool {
            state.withLock {
                guard !$0.isCancelled else { return false }
                $0.commands = commands
                return true
            }
        }

        func cancel() -> [PendingCommand] {
            state.withLock {
                $0.isCancelled = true
                return $0.commands
            }
        }
    }

    private final class PendingPipeline: Sendable {
        private typealias Completion = (
            continuation: CheckedContinuation<[RESPValue], Error>,
            result: Result<[RESPValue], Error>
        )

        private struct State: Sendable {
            var results: [RESPValue?]
            var remainingCount: Int
            var continuation: CheckedContinuation<[RESPValue], Error>?
        }

        private let state: Mutex<State>

        init(count: Int, continuation: CheckedContinuation<[RESPValue], Error>) {
            state = Mutex(
                State(
                    results: Array(repeating: nil, count: count),
                    remainingCount: count,
                    continuation: continuation
                )
            )
        }

        func complete(index: Int, with result: Result<RESPValue, Error>) {
            let completion: Completion? = state.withLock { state in
                if let storedContinuation = state.continuation {
                    switch result {
                    case .success(let value):
                        state.results[index] = value
                        state.remainingCount -= 1
                        if state.remainingCount == 0 {
                            var values: [RESPValue] = []
                            values.reserveCapacity(state.results.count)
                            var missingResponse = false
                            for response in state.results {
                                guard let response else {
                                    missingResponse = true
                                    break
                                }
                                values.append(response)
                            }

                            state.continuation = nil
                            return (
                                storedContinuation,
                                missingResponse
                                    ? .failure(RedisError.parseError("Missing Redis pipeline response"))
                                    : .success(values)
                            )
                        }
                    case .failure(let error):
                        state.continuation = nil
                        return (storedContinuation, .failure(error))
                    }
                }
                return nil
            }

            guard let completion else { return }
            switch completion.result {
            case .success(let values):
                completion.continuation.resume(returning: values)
            case .failure(let error):
                completion.continuation.resume(throwing: error)
            }
        }
    }

    private enum PendingResponse: Sendable {
        case command(PendingCommand)
        case cancelled(UUID)

        var id: UUID {
            switch self {
            case .command(let command):
                command.id
            case .cancelled(let id):
                id
            }
        }

        var command: PendingCommand? {
            guard case .command(let command) = self else { return nil }
            return command
        }
    }

    private struct State: Sendable {
        var connection: NWConnection?
        var pendingCompletions: [PendingResponse] = []
        var parser = RESPParser()
        var isConnected = false
        var lastError: String?
        var negotiatedProtocolVersion: RESPProtocolVersion = .resp2
        var serverCapabilities: [String: RESPValue] = [:]
        var protocolFallbackReason: String?
    }

    private let state = Mutex(State())
    private let queue = DispatchQueue(label: "redis.client.queue")
    private let queueKey = DispatchSpecificKey<Bool>()

    var isConnected: Bool {
        state.withLock { $0.isConnected }
    }

    var lastError: String? {
        state.withLock { $0.lastError }
    }

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
    let connectionTimeout: TimeInterval

    private var negotiatedProtocolVersion: RESPProtocolVersion {
        get { state.withLock { $0.negotiatedProtocolVersion } }
        set { state.withLock { $0.negotiatedProtocolVersion = newValue } }
    }

    private var serverCapabilities: [String: RESPValue] {
        get { state.withLock { $0.serverCapabilities } }
        set { state.withLock { $0.serverCapabilities = newValue } }
    }

    private var protocolFallbackReason: String? {
        get { state.withLock { $0.protocolFallbackReason } }
        set { state.withLock { $0.protocolFallbackReason = newValue } }
    }

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
        preferredProtocolVersion: RESPProtocolVersion = .resp3,
        connectionTimeout: TimeInterval = 10
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
        self.connectionTimeout = connectionTimeout
        queue.setSpecific(key: queueKey, value: true)
    }

    func connect() async throws {
        try Task.checkCancellation()
        let connectContinuation = ConnectContinuationState()
        let staleCompletions = state.withLock {
            let pendingCompletions = $0.pendingCompletions.compactMap(\.command)
            $0.isConnected = false
            $0.lastError = nil
            $0.pendingCompletions.removeAll()
            $0.parser = RESPParser()
            $0.negotiatedProtocolVersion = .resp2
            $0.serverCapabilities = [:]
            $0.protocolFallbackReason = nil
            return pendingCompletions
        }
        for completion in staleCompletions {
            completion.complete(.failure(RedisError.notConnected))
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connectContinuation.setContinuation(continuation)
                guard !connectContinuation.isCompleted else { return }
                guard !Task.isCancelled else {
                    connectContinuation.complete(.failure(CancellationError()))
                    return
                }

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
                    connectContinuation.complete(.failure(RedisError.commandError("Invalid Redis port: \(port)")))
                    return
                }

                let connection = NWConnection(
                    host: NWEndpoint.Host(host),
                    port: nwPort,
                    using: params
                )
                state.withLock {
                    $0.connection = connection
                }
                guard !connectContinuation.isCompleted else {
                    cancelConnectionForCancellation()
                    return
                }

                connection.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard !connectContinuation.isCompleted else { return }
                        self.updateConnectionState(isConnected: true)
                        self.startReceiving()

                        Task {
                            guard !connectContinuation.isCompleted else { return }
                            do {
                                var authenticatedByHello = false
                                if self.preferredProtocolVersion == .resp3 {
                                    authenticatedByHello = try await self.performResp3Handshake()
                                }

                                // Authenticate if credentials are provided.
                                let user = self.username ?? ""
                                let pw = self.password ?? ""
                                if (!user.isEmpty || !pw.isEmpty) && !authenticatedByHello {
                                    let result: RESPValue
                                    if !user.isEmpty {
                                        result = try await self.send("AUTH", user, pw)
                                    } else {
                                        result = try await self.send("AUTH", pw)
                                    }
                                    if case .error(let msg) = result {
                                        self.updateConnectionState(isConnected: true, lastError: msg)
                                        throw RedisError.commandError(msg)
                                    }
                                }
                                self.logNegotiatedProtocol(authenticatedByHello: authenticatedByHello)

                                connectContinuation.complete(.success(()))
                            } catch {
                                self.updateConnectionState(isConnected: false, lastError: error.localizedDescription)
                                connectContinuation.complete(.failure(error))
                            }
                        }
                    case .failed(let error):
                        self.updateConnectionState(isConnected: false, lastError: error.localizedDescription)
                        connectContinuation.complete(.failure(error))
                    case .waiting(let error):
                        self.updateConnectionState(lastError: error.localizedDescription)
                    case .cancelled:
                        self.updateConnectionState(isConnected: false)
                        connectContinuation.complete(.failure(RedisError.notConnected))
                    default:
                        break
                    }
                }

                connection.start(queue: queue)
            }
        } onCancel: {
            connectContinuation.complete(.failure(CancellationError()))
            self.cancelConnectionForCancellation()
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

    private func updateConnectionState(isConnected: Bool? = nil, lastError: String? = nil) {
        state.withLock {
            if let isConnected {
                $0.isConnected = isConnected
            }
            if let lastError {
                $0.lastError = lastError
            }
        }
    }

    private func removePendingCompletion(_ completion: PendingCommand) {
        removePendingCompletion(id: completion.id)
    }

    private func removePendingCompletion(id: UUID) {
        state.withLock { state in
            if let index = state.pendingCompletions.firstIndex(where: { $0.id == id }) {
                state.pendingCompletions.remove(at: index)
            }
        }
    }

    private func cancelPendingResponseSlot(id: UUID) {
        state.withLock { state in
            if let index = state.pendingCompletions.firstIndex(where: { $0.id == id }) {
                state.pendingCompletions[index] = .cancelled(id)
            }
        }
    }

    private func failPendingCompletion(_ completion: PendingCommand, with error: Error) {
        removePendingCompletion(completion)
        completion.complete(.failure(error))
    }

    private func cancelPendingCompletion(_ completion: PendingCommand) {
        let cancelAction: @Sendable () -> Void = {
            let shouldRemoveFromQueue = completion.cancel()
            if shouldRemoveFromQueue {
                self.removePendingCompletion(completion)
            } else {
                self.cancelPendingResponseSlot(id: completion.id)
            }
        }

        if DispatchQueue.getSpecific(key: queueKey) == true {
            cancelAction()
        } else {
            queue.async(execute: cancelAction)
        }
    }

    private func cancelPendingCompletions(_ batch: PendingCommandBatch) {
        for command in batch.cancel() {
            cancelPendingCompletion(command)
        }
    }

    private func receiveLoop() {
        queue.async {
            let connection = self.state.withLock { $0.connection }
            connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.queue.async {
                        self.state.withLock {
                            $0.parser.append(data)
                        }
                        self.processBuffer()
                    }
                }
                if error == nil && !isComplete {
                    self.receiveLoop()
                } else {
                    self.queue.async {
                        self.completePendingCommands(with: error ?? RedisError.notConnected)
                        self.state.withLock {
                            $0.parser = RESPParser()
                        }
                    }
                    self.updateConnectionState(isConnected: false, lastError: error?.localizedDescription)
                }
            }
        }
    }

    private func completePendingCommands(with error: Error) {
        let pendingCompletions = state.withLock {
            let pendingCompletions = $0.pendingCompletions.compactMap(\.command)
            $0.pendingCompletions.removeAll()
            return pendingCompletions
        }
        for completion in pendingCompletions {
            completion.complete(.failure(error))
        }
    }

    private func cancelConnectionOnQueue(error: Error = RedisError.notConnected) {
        let connection = state.withLock {
            let connection = $0.connection
            $0.connection = nil
            $0.parser = RESPParser()
            return connection
        }
        connection?.cancel()
        completePendingCommands(with: error)
    }

    private func cancelConnectionForCancellation() {
        let cancelAction: @Sendable () -> Void = {
            self.cancelConnectionOnQueue(error: CancellationError())
        }

        if DispatchQueue.getSpecific(key: queueKey) == true {
            cancelAction()
        } else {
            queue.async(execute: cancelAction)
        }
        updateConnectionState(isConnected: false)
    }

    private func startReceiving() {
        receiveLoop()
    }

    private func processBuffer() {
        let completedCommands: [(PendingCommand, RESPValue)] = state.withLock {
            var completedCommands: [(PendingCommand, RESPValue)] = []
            while let value = $0.parser.parse() {
                guard !$0.pendingCompletions.isEmpty else { continue }
                let pendingResponse = $0.pendingCompletions.removeFirst()
                if let completion = pendingResponse.command {
                    completedCommands.append((completion, value))
                }
            }
            return completedCommands
        }

        for (completion, value) in completedCommands {
            completion.complete(.success(value))
        }
    }

    func send(_ args: String...) async throws -> RESPValue {
        try await send(args)
    }

    func send(_ args: [String]) async throws -> RESPValue {
        let data = RESPEncoder.encode(args, version: negotiatedProtocolVersion)
        return try await sendEncodedCommand(data)
    }

    private func sendEncodedCommand(_ data: Data) async throws -> RESPValue {
        try Task.checkCancellation()
        guard isConnected else {
            throw RedisError.notConnected
        }

        let pendingCompletion = PendingCommand()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingCompletion.setContinuation(continuation)

                self.queue.async {
                    guard !pendingCompletion.isCompleted else { return }
                    guard let connection = self.state.withLock({ $0.connection }) else {
                        pendingCompletion.complete(.failure(RedisError.notConnected))
                        return
                    }
                    guard pendingCompletion.reserveResponseSlot() else { return }

                    self.state.withLock {
                        $0.pendingCompletions.append(.command(pendingCompletion))
                    }

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
        } onCancel: {
            self.cancelPendingCompletion(pendingCompletion)
        }
    }

    func sendPipeline(_ commands: [[String]]) async throws -> [RESPValue] {
        try Task.checkCancellation()
        guard isConnected else {
            throw RedisError.notConnected
        }
        guard !commands.isEmpty else { return [] }
        guard commands.allSatisfy({ !$0.isEmpty }) else {
            throw RedisError.commandError("Redis command is empty")
        }

        let data = commands.reduce(into: Data()) { encodedData, command in
            encodedData.append(RESPEncoder.encode(command, version: negotiatedProtocolVersion))
        }

        let pendingBatch = PendingCommandBatch()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let pipeline = PendingPipeline(count: commands.count, continuation: continuation)
                let pendingCommands = commands.indices.map { index in
                    PendingCommand(completion: { result in
                        pipeline.complete(index: index, with: result)
                    })
                }

                guard pendingBatch.setCommands(pendingCommands) else {
                    for pendingCommand in pendingCommands {
                        pendingCommand.complete(.failure(CancellationError()))
                    }
                    return
                }

                self.queue.async {
                    guard pendingCommands.allSatisfy({ !$0.isCompleted }) else { return }
                    guard let connection = self.state.withLock({ $0.connection }) else {
                        for pendingCommand in pendingCommands {
                            pendingCommand.complete(.failure(RedisError.notConnected))
                        }
                        return
                    }
                    for pendingCommand in pendingCommands {
                        guard pendingCommand.reserveResponseSlot() else { return }
                    }

                    self.state.withLock {
                        $0.pendingCompletions.append(contentsOf: pendingCommands.map(PendingResponse.command))
                    }

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
        } onCancel: {
            self.cancelPendingCompletions(pendingBatch)
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

        return try await sendEncodedCommand(data)
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

        state.withLock {
            $0.serverCapabilities.merge(normalizedHelloCapabilities(from: result.keyValuePairs)) { _, new in new }
            $0.negotiatedProtocolVersion = .resp2
            $0.serverCapabilities["proto"] = .integer(2)
            $0.protocolFallbackReason = fallbackReason
        }
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

    var isUnknownCommand: Bool {
        guard case .commandError(let message) = self else { return false }
        return message.localizedCaseInsensitiveContains("unknown command")
    }
}
