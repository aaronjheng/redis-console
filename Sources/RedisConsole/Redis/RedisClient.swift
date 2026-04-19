import Combine
import Foundation
import Network

@available(macOS 14.0, *)
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

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "redis.client.queue")
    private var pendingCompletions: [(Result<RESPValue, Error>) -> Void] = []
    private var parser = RESPParser()

    @Published var isConnected = false
    @Published var lastError: String?

    let host: String
    let port: UInt16
    let password: String?
    let preferredProtocolVersion: RESPProtocolVersion

    private(set) var negotiatedProtocolVersion: RESPProtocolVersion = .resp2
    private(set) var serverCapabilities: [String: RESPValue] = [:]

    init(
        host: String,
        port: UInt16,
        password: String? = nil,
        preferredProtocolVersion: RESPProtocolVersion = .resp3
    ) {
        self.host = host
        self.port = port
        self.password = password
        self.preferredProtocolVersion = preferredProtocolVersion
    }

    func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let continuationState = ConnectContinuationState()

            let params = NWParameters.tcp
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

                                // Authenticate if password provided
                                if let pw = self?.password, !pw.isEmpty {
                                    let result = try await self?.send("AUTH", pw) ?? .null
                                    if case .error(let msg) = result {
                                        self?.lastError = msg
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
                    default:
                        break
                    }
                }
            }

            connection?.start(queue: queue)
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        pendingCompletions.removeAll()
        parser = RESPParser()
    }

    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.queue.async {
                    self.parser.append(data)
                    self.processBuffer()
                }
            }
            if error == nil {
                self.startReceiving()
            } else {
                Task { @MainActor in
                    self.isConnected = false
                    self.lastError = error?.localizedDescription
                }
            }
        }
    }

    private func processBuffer() {
        while let value = parser.parse() {
            if let completion = pendingCompletions.first {
                pendingCompletions.removeFirst()
                completion(.success(value))
            }
        }
    }

    func send(_ args: String...) async throws -> RESPValue {
        try await send(args)
    }

    func send(_ args: [String]) async throws -> RESPValue {
        guard isConnected, let connection = connection else {
            throw RedisError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Use negotiated protocol version for encoding
            let data = RESPEncoder.encode(args, version: negotiatedProtocolVersion)

            self.queue.async {
                self.pendingCompletions.append { result in
                    switch result {
                    case .success(let value):
                        continuation.resume(returning: value)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                connection.send(
                    content: data,
                    completion: .contentProcessed { error in
                        if let error = error {
                            self.queue.async {
                                if !self.pendingCompletions.isEmpty {
                                    self.pendingCompletions.removeFirst()
                                }
                            }
                            continuation.resume(throwing: error)
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
            self.queue.async {
                self.pendingCompletions.append { result in
                    switch result {
                    case .success(let value):
                        continuation.resume(returning: value)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                self.connection?.send(
                    content: data,
                    completion: .contentProcessed { error in
                        if let error = error {
                            self.queue.async {
                                if !self.pendingCompletions.isEmpty {
                                    self.pendingCompletions.removeFirst()
                                }
                            }
                            continuation.resume(throwing: error)
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
        disconnect()
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
