import Foundation
import Observation

// MARK: - App Store (Global singleton, shared across all tabs)

@MainActor
@Observable
class AppStore {
    static let shared = AppStore()

    var connections: [RedisConnectionConfig] = []
    private let storeURL: URL

    private init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            connections = [.default]
            storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("connections.json")
            return
        }
        let dir = appSupport.appendingPathComponent("redis.console", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("connections.json")
        loadConnections()
    }

    func loadConnections() {
        if let data = try? Data(contentsOf: storeURL) {
            let decoded = try? JSONDecoder().decode([RedisConnectionConfig].self, from: data)
            if let decoded {
                connections = decoded
            }
        }
        if connections.isEmpty {
            connections = [.default]
        }
    }

    func saveConnections() {
        if let data = try? JSONEncoder().encode(connections) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    func addConnection(_ config: RedisConnectionConfig) {
        connections.append(config)
        saveConnections()
    }

    func updateConnection(_ config: RedisConnectionConfig) {
        if let idx = connections.firstIndex(where: { $0.id == config.id }) {
            connections[idx] = config
            saveConnections()
        }
    }

    func deleteConnection(_ config: RedisConnectionConfig) {
        connections.removeAll { $0.id == config.id }
        saveConnections()
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
        }
        saveConnections()
    }
}
