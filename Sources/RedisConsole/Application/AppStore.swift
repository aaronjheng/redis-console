import Foundation
import SwiftUI

// MARK: - App Store (Global singleton, shared across all tabs)

@MainActor
class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var connections: [RedisConnectionConfig] = []
    private let storeURL: URL
    private let secretsAccountSuffix = "secrets"

    private struct ConnectionSecrets: Codable {
        let redisPassword: String
        let sshPassword: String
        let sshPrivateKeyPassphrase: String

        var isEmpty: Bool {
            redisPassword.isEmpty && sshPassword.isEmpty && sshPrivateKeyPassphrase.isEmpty
        }
    }

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
                connections = decoded.map { config in
                    var resolved = config
                    loadSecretsFromKeychain(into: &resolved)
                    return resolved
                }
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
        saveSecretsToKeychain(for: config)
        saveConnections()
    }

    func updateConnection(_ config: RedisConnectionConfig) {
        if let idx = connections.firstIndex(where: { $0.id == config.id }) {
            connections[idx] = config
            saveSecretsToKeychain(for: config)
            saveConnections()
        }
    }

    func deleteConnection(_ config: RedisConnectionConfig) {
        connections.removeAll { $0.id == config.id }
        deleteSecretsFromKeychain(for: config)
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
            saveSecretsToKeychain(for: newConfig)
        }
        saveConnections()
    }

    private func keychainAccount(for id: UUID) -> String {
        "connection.\(id.uuidString).\(secretsAccountSuffix)"
    }

    private func saveSecretsToKeychain(for config: RedisConnectionConfig) {
        let secrets = ConnectionSecrets(
            redisPassword: config.password,
            sshPassword: config.ssh.password,
            sshPrivateKeyPassphrase: config.ssh.privateKeyPassphrase
        )
        if secrets.isEmpty {
            KeychainStore.deletePassword(account: keychainAccount(for: config.id))
            return
        }

        guard let encoded = try? JSONEncoder().encode(secrets) else {
            AppLogger.error("saveSecretsToKeychain JSON encode failed connectionId=\(config.id.uuidString)", category: "AppStore")
            return
        }
        guard let payload = String(data: encoded, encoding: .utf8) else {
            AppLogger.error("saveSecretsToKeychain UTF-8 conversion failed connectionId=\(config.id.uuidString)", category: "AppStore")
            return
        }

        let saved = KeychainStore.setPassword(payload, account: keychainAccount(for: config.id))
        if !saved {
            AppLogger.error("failed to save secrets to keychain connectionId=\(config.id.uuidString)", category: "AppStore")
        }
    }

    private func loadSecretsFromKeychain(into config: inout RedisConnectionConfig) {
        let connectionId = config.id.uuidString
        guard let payload = KeychainStore.getPassword(account: keychainAccount(for: config.id)) else {
            config.password = ""
            config.ssh.password = ""
            config.ssh.privateKeyPassphrase = ""
            return
        }
        guard let data = payload.data(using: .utf8) else {
            AppLogger.error("loadSecretsFromKeychain payload not UTF-8 connectionId=\(connectionId)", category: "AppStore")
            config.password = ""
            config.ssh.password = ""
            config.ssh.privateKeyPassphrase = ""
            return
        }
        guard let decoded = try? JSONDecoder().decode(ConnectionSecrets.self, from: data) else {
            AppLogger.error("loadSecretsFromKeychain JSON decode failed connectionId=\(connectionId)", category: "AppStore")
            config.password = ""
            config.ssh.password = ""
            config.ssh.privateKeyPassphrase = ""
            return
        }
        config.password = decoded.redisPassword
        config.ssh.password = decoded.sshPassword
        config.ssh.privateKeyPassphrase = decoded.sshPrivateKeyPassphrase
    }

    private func deleteSecretsFromKeychain(for config: RedisConnectionConfig) {
        KeychainStore.deletePassword(account: keychainAccount(for: config.id))
    }
}
