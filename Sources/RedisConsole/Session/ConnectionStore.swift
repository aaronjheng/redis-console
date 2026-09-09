import Foundation
import Observation

// MARK: - Connection Store (Global singleton, shared across all tabs)

@MainActor
@Observable
class ConnectionStore {
    static let shared = ConnectionStore()

    var connections: [RedisConnectionConfig] = []
    private let database = AppDatabase.shared

    private init() {
        connections = database.loadConnections()
        if connections.isEmpty {
            connections = [.default]
        }
    }

    func addConnection(_ config: RedisConnectionConfig) {
        connections.append(config)
        database.insertConnection(config)
    }

    func updateConnection(_ config: RedisConnectionConfig) {
        if let idx = connections.firstIndex(where: { $0.id == config.id }) {
            connections[idx] = config
            database.updateConnection(config)
        }
    }

    func deleteConnection(_ config: RedisConnectionConfig) {
        connections.removeAll { $0.id == config.id }
        database.deleteConnection(id: config.id)
    }

    func exportConnections(_ configs: [RedisConnectionConfig]) -> Data? {
        try? JSONEncoder().encode(configs)
    }

    func importConnections(from data: Data) -> [RedisConnectionConfig]? {
        try? JSONDecoder().decode([RedisConnectionConfig].self, from: data)
    }

    func addImportedConnections(_ configs: [RedisConnectionConfig]) {
        for config in configs {
            var newConfig = config
            newConfig.id = UUID()
            connections.append(newConfig)
            database.insertConnection(newConfig)
        }
    }
}
