import Combine
import Foundation
import Network

@available(macOS 14.0, *)
class RedisClient: ObservableObject, @unchecked Sendable {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "redis.client.queue")
    private var pendingCompletions: [(Result<RESPValue, Error>) -> Void] = []
    private var parser = RESPParser()

    @Published var isConnected = false
    @Published var lastError: String?

    let host: String
    let port: UInt16
    let password: String?

    init(host: String, port: UInt16, password: String? = nil) {
        self.host = host
        self.port = port
        self.password = password
    }

    func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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
                        if let pw = self?.password, !pw.isEmpty {
                            Task {
                                do {
                                    let result = try await self?.send("AUTH", pw) ?? .null
                                    if case .error(let msg) = result {
                                        self?.lastError = msg
                                    }
                                } catch {
                                    self?.lastError = error.localizedDescription
                                }
                            }
                        }
                        continuation.resume()
                    case .failed(let error):
                        self?.isConnected = false
                        self?.lastError = error.localizedDescription
                        continuation.resume(throwing: error)
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
            let data = RESPEncoder.encode(args)

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
