import AppKit
import SwiftUI

// MARK: - Workspace Sidebar

struct WorkspaceSidebarView: View {
    @Environment(ConnectionState.self) private var conn

    var body: some View {
        @Bindable var conn = conn

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if let selectedConnection = conn.selectedConnection {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: AppTheme.spacingSmall) {
                            Text(selectedConnection.name)
                                .font(.title3)
                                .fontWeight(.bold)
                                .lineLimit(1)
                            Spacer(minLength: AppTheme.spacing)
                            Badge(
                                text: selectedConnection.mode.title,
                                foregroundColor: selectedConnection.mode.badgeForegroundColor,
                                backgroundColor: selectedConnection.mode.badgeBackgroundColor
                            )
                            .help("Connection mode: \(selectedConnection.mode.title)")
                        }

                        Text(selectedConnection.address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
            }

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
