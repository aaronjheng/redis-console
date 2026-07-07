import AppKit
import SwiftUI

// MARK: - Connection Hub Sidebar

struct ConnectionHubSidebarView: View {
    @Environment(ConnectionState.self) private var conn
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Connections")
                    .font(.headline)
                Spacer()
                Button("Export All Connections", systemImage: "square.and.arrow.up") {
                    exportConnections(store.connections)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Export All Connections")
                Button("Import Connections", systemImage: "square.and.arrow.down") {
                    importConnections()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Import Connections")
                Button("New Connection", systemImage: "plus") {
                    conn.selectedConnection = nil
                    conn.rightPanel = .newConnection
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            .padding(16)

            Divider()

            List(
                selection: Binding(
                    get: { conn.selectedConnection },
                    set: {
                        conn.selectedConnection = $0
                        if let selectedConnection = $0 {
                            conn.rightPanel = .editConnection(selectedConnection)
                        }
                    }
                )
            ) {
                ForEach(store.connections) { config in
                    ConnectionRow(config: config, isConnected: false)
                        .tag(config)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .overlay(
                            DoubleClickHandler {
                                Task { await conn.connect(to: config) }
                            }
                        )
                        .contextMenu {
                            Button("Duplicate") {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(config.address, forType: .string)
                            }
                            Button("Delete") {
                                store.deleteConnection(config)
                                if conn.selectedConnection?.id == config.id {
                                    conn.selectedConnection = nil
                                    conn.rightPanel = .welcome
                                }
                            }
                            Divider()
                            Button("Copy URI") {
                                var uri = "redis://"
                                if !config.username.isEmpty || !config.password.isEmpty {
                                    if !config.username.isEmpty {
                                        uri += config.username
                                    }
                                    if !config.password.isEmpty {
                                        uri += ":\(config.password)"
                                    }
                                    uri += "@"
                                }
                                uri += "\(config.host):\(config.port)"
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(uri, forType: .string)
                            }
                            Divider()
                            Button("Export...") {
                                exportConnections([config])
                            }
                        }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func exportConnections(_ configs: [RedisConnectionConfig]) {
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

    private func importConnections() {
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
