import AppKit
import SwiftUI

// MARK: - Workspace Sidebar

struct WorkspaceSidebarView: View {
    @EnvironmentObject var conn: ConnectionState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    if let selectedConnection = conn.selectedConnection {
                        HStack(spacing: AppTheme.spacingSmall) {
                            Text(selectedConnection.name)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer(minLength: AppTheme.spacing)
                            ConnectionModeBadge(mode: selectedConnection.mode)
                        }
                        Text(selectedConnection.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()

            Divider()

            List(selection: $conn.currentView) {
                ForEach(AppView.allCases, id: \.self) { view in
                    Label(view.rawValue, systemImage: view.icon)
                        .tag(view)
                }
            }
            .listStyle(.sidebar)

            Divider()

            WorkspaceFooterBar {
                Button(role: .destructive) {
                    conn.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "power")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Disconnect")
            }
        }
    }
}

// MARK: - Connection Hub Sidebar

struct ConnectionHubSidebarView: View {
    @EnvironmentObject var conn: ConnectionState
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Connections")
                    .font(.headline)
                Spacer()
                Button {
                    exportConnections(store.connections)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help("Export All Connections")
                Button {
                    importConnections()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .help("Import Connections")
                Button {
                    conn.selectedConnection = nil
                    conn.rightPanel = .newConnection
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding()

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
