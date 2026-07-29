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
                    ConnectionTransfer.export(store.connections, store: store)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Export All Connections")
                Button("Import Connections", systemImage: "square.and.arrow.down") {
                    ConnectionTransfer.importConfigurations(store: store)
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
                                ConnectionTransfer.export([config], store: store)
                            }
                        }
                }
            }
            .listStyle(.sidebar)
        }
    }
}
