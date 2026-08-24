import SwiftUI

// MARK: - Connection Hub Sidebar

struct ConnectionHubSidebarView: View {
    @Environment(ConnectionState.self) private var conn
    @Environment(AppStore.self) private var store
    @State private var connectionPendingDeletion: RedisConnectionConfig?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportDocument: ConnectionsDocument?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Connections")
                    .font(.headline)
                Spacer()
                Button("Export All Connections", systemImage: "square.and.arrow.up") {
                    beginExport(store.connections)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Export All Connections")
                Button("Import Connections", systemImage: "square.and.arrow.down") {
                    isImporting = true
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
                .help("New Connection")
            }
            .padding(AppSpacing.large)

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
                            Button("Connect") {
                                Task { await conn.connect(to: config) }
                            }
                            Button("Duplicate") {
                                var copy = config
                                copy.id = UUID()
                                copy.name = "\(config.name) Copy"
                                store.addConnection(copy)
                                conn.selectedConnection = copy
                                conn.rightPanel = .editConnection(copy)
                            }
                            Button("Delete", role: .destructive) {
                                connectionPendingDeletion = config
                            }
                            Divider()
                            Button("Copy Address") {
                                copyToPasteboard(config.address)
                            }
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
                                copyToPasteboard(uri)
                            }
                            Divider()
                            Button("Export...") {
                                beginExport([config])
                            }
                        }
                }
            }
            .listStyle(.sidebar)
        }
        .confirmationDialog(
            "Delete Connection?",
            isPresented: Binding(
                get: { connectionPendingDeletion != nil },
                set: { if !$0 { connectionPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let config = connectionPendingDeletion {
                Button("Delete \"\(config.name)\"", role: .destructive) {
                    store.deleteConnection(config)
                    if conn.selectedConnection?.id == config.id {
                        conn.selectedConnection = nil
                        conn.rightPanel = .welcome
                    }
                    connectionPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                connectionPendingDeletion = nil
            }
        } message: {
            if let config = connectionPendingDeletion {
                Text("This permanently deletes \"\(config.name)\" (\(config.address)).")
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportDocument?.defaultFilename
        ) { _ in }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            ConnectionTransfer.importConnections(from: result, store: store)
        }
    }

    private func beginExport(_ configs: [RedisConnectionConfig]) {
        guard let document = ConnectionTransfer.exportDocument(for: configs, store: store) else { return }
        exportDocument = document
        isExporting = true
    }
}
