import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Connection Transfer

/// Panel-based import/export of connection configs, shared by the connection
/// sidebar and the welcome screen.
@MainActor
enum ConnectionTransfer {
    static func export(_ configs: [RedisConnectionConfig], store: AppStore) {
        guard let data = store.exportConnections(configs) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue =
            configs.count == 1
            ? "\(configs[0].name).json"
            : "redis-connections.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    static func importConfigurations(store: AppStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url),
                let configs = store.importConnections(from: data)
            else { return }
            store.addImportedConnections(configs)
        }
    }
}
