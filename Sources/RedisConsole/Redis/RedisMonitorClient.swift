import Foundation
import Network

final class RedisMonitorClient: @unchecked Sendable {
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

    private let queue = DispatchQueue(label: "redis.monitor.client.queue")
    private let queueKey = DispatchSpecificKey<Bool>()
    private var connection: NWConnection?
    private var pendingCompletions: [PendingCommand] = []
    private var parser = RESPParser()
    private var isConnected = false
    private var isMonitoring = false
    private var monitorContinuation: AsyncThrowingStream<String, Error>.Continuation?

    private let host: String
    private let port: UInt16
    private let username: String?
    private let password: String?
    private let tlsEnabled: Bool
    private let verifyServerCertificate: Bool
    private let caCertificatePath: String
    private let clientCertificatePath: String
    private let clientKeyPath: String

    init(
        host: String,
        port: UInt16,
        username: String? = nil,
        password: String? = nil,
        tlsEnabled: Bool = false,
        verifyServerCertificate: Bool = true,
        caCertificatePath: String = "",
        clientCertificatePath: String = "",
        clientKeyPath: String = ""
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
        queue.setSpecific(key: queueKey, value: true)
    }

    func startMonitoring() async throws -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream(
            of: String.self,
            throwing: Error.self,
            bufferingPolicy: .bufferingNewest(2_000)
        )

        runOnQueue {
            self.monitorContinuation = continuation
        }

        continuation.onTermination = { [weak self] _ in
            self?.disconnect()
        }

        do {
            try await connect()
            try await authenticateIfNeeded()
            runOnQueue {
                self.isMonitoring = true
            }

            let result = try await send("MONITOR")
            guard case .simpleString(let message) = result, message.uppercased() == "OK" else {
                if case .error(let message) = result {
                    throw RedisError.commandError(message)
                }
                throw RedisError.commandError("Unexpected MONITOR response: \(result.displayString)")
            }

            return stream
        } catch {
            disconnect()
            throw error
        }
    }

    func disconnect() {
        runOnQueue {
            self.cancelConnectionOnQueue(finishError: nil)
        }
    }

    private func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let continuationState = ConnectContinuationState()
            let params = makeConnectionParameters()

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(throwing: RedisError.commandError("Invalid Redis port: \(port)"))
                return
            }

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: params
            )
            self.connection = connection

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }

                switch state {
                case .ready:
                    self.isConnected = true
                    self.receiveLoop()
                    if continuationState.tryMarkResumed() {
                        continuation.resume()
                    }
                case .failed(let error):
                    self.isConnected = false
                    self.completePendingCommands(with: error)
                    self.finishMonitor(with: error)
                    if continuationState.tryMarkResumed() {
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
                    self.isConnected = false
                    if continuationState.tryMarkResumed() {
                        continuation.resume(throwing: RedisError.notConnected)
                    }
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }

    private func makeConnectionParameters() -> NWParameters {
        guard tlsEnabled else {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            return params
        }

        let tlsOptions = NWProtocolTLS.Options()

        if !caCertificatePath.isEmpty || !clientCertificatePath.isEmpty || !clientKeyPath.isEmpty {
            sec_protocol_options_set_verify_block(
                tlsOptions.securityProtocolOptions,
                { [caCertificatePath] _, trust, completionHandler in
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

        let params = NWParameters(tls: tlsOptions, tcp: .init())
        params.allowLocalEndpointReuse = true
        return params
    }

    private func authenticateIfNeeded() async throws {
        let user = username ?? ""
        let pw = password ?? ""
        guard !user.isEmpty || !pw.isEmpty else { return }

        let result: RESPValue
        if user.isEmpty {
            result = try await send("AUTH", pw)
        } else {
            result = try await send("AUTH", user, pw)
        }

        if case .error(let message) = result {
            throw RedisError.commandError(message)
        }
    }

    private func receiveLoop() {
        queue.async {
            self.receiveOnQueue()
        }
    }

    private func receiveOnQueue() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            self?.handleReceive(data: data, isComplete: isComplete, error: error)
        }
    }

    private func handleReceive(data: Data?, isComplete: Bool, error: NWError?) {
        if let data, !data.isEmpty {
            queue.async {
                self.parser.append(data)
                self.processBuffer()
            }
        }

        if error == nil && !isComplete {
            receiveLoop()
        } else {
            queue.async {
                let finishError: Error = error ?? RedisError.notConnected
                self.completePendingCommands(with: finishError)
                self.parser = RESPParser()
                self.isConnected = false
                self.finishMonitor(with: finishError)
            }
        }
    }

    private func processBuffer() {
        while let value = parser.parse() {
            if let completion = pendingCompletions.first {
                pendingCompletions.removeFirst()
                completion.complete(.success(value))
            } else if isMonitoring, let line = value.string {
                monitorContinuation?.yield(line)
            } else if case .error(let message) = value {
                finishMonitor(with: RedisError.commandError(message))
            }
        }
    }

    private func send(_ args: String...) async throws -> RESPValue {
        try await send(args)
    }

    private func send(_ args: [String]) async throws -> RESPValue {
        try await withCheckedThrowingContinuation { continuation in
            let data = RESPEncoder.encode(args)
            let pendingCompletion = PendingCommand(continuation)

            self.queue.async {
                guard let connection = self.connection, self.isConnected else {
                    pendingCompletion.complete(.failure(RedisError.notConnected))
                    return
                }

                self.pendingCompletions.append(pendingCompletion)

                connection.send(
                    content: data,
                    completion: .contentProcessed { error in
                        if let error {
                            self.queue.async {
                                self.failPendingCompletion(pendingCompletion, with: error)
                            }
                        }
                    })
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

    private func completePendingCommands(with error: Error) {
        let pendingCompletions = pendingCompletions
        self.pendingCompletions.removeAll()
        for completion in pendingCompletions {
            completion.complete(.failure(error))
        }
    }

    private func cancelConnectionOnQueue(finishError: Error?) {
        connection?.cancel()
        connection = nil
        isConnected = false
        isMonitoring = false
        completePendingCommands(with: finishError ?? RedisError.notConnected)
        parser = RESPParser()
        finishMonitor(with: finishError)
    }

    private func finishMonitor(with error: Error?) {
        let continuation = monitorContinuation
        monitorContinuation = nil
        isMonitoring = false

        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
    }

    private func runOnQueue(_ action: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) == true {
            action()
        } else {
            queue.sync(execute: action)
        }
    }

    deinit {
        disconnect()
    }
}
