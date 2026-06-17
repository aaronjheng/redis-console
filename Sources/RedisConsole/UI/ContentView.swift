import AppKit
import SwiftUI

// MARK: - Tab Content View (per-tab)

struct TabContentView: View {
    @Environment(ConnectionState.self) private var conn

    var body: some View {
        Group {
            if conn.activeClient?.isConnected == true {
                WorkspaceView()
            } else {
                ConnectionHubView()
            }
        }
        .background(WindowTitleUpdater())
    }
}

// MARK: - Connection Hub View

struct ConnectionHubView: View {
    @Environment(ConnectionState.self) private var conn
    @State private var cachedRightPanel: RightPanel = .welcome

    var body: some View {
        HSplitView {
            ConnectionHubSidebarView()
                .frame(minWidth: 220, maxWidth: 280)

            if conn.isConnecting {
                ConnectingView()
            } else {
                switch cachedRightPanel {
                case .editConnection, .newConnection:
                    ConnectionDetailView()
                        .frame(minWidth: 400)
                case .welcome:
                    WelcomeView()
                }
            }
        }
        .onChange(of: conn.rightPanel) { _, newValue in
            cachedRightPanel = newValue
        }
        .onAppear {
            cachedRightPanel = conn.rightPanel
        }
    }
}

// MARK: - Workspace View

struct WorkspaceView: View {
    @Environment(ConnectionState.self) private var conn

    var body: some View {
        HSplitView {
            WorkspaceSidebarView()
                .frame(minWidth: 220, maxWidth: 280)

            switch conn.currentView {
            case .browser: BrowserView()
            case .shell: ShellView()
            case .profiler: ProfilerView()
            case .slowLog: SlowLogView()
            case .databaseAnalysis: DatabaseAnalysisView()
            case .serverInfo: ServerInfoView()
            }
        }
    }
}

// MARK: - Window Title Updater

struct WindowTitleUpdater: NSViewRepresentable {
    @Environment(ConnectionState.self) private var conn

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        conn.window = window
        if let client = conn.activeClient, client.isConnected, let selectedConnection = conn.selectedConnection {
            window.title = "\(selectedConnection.name) — \(selectedConnection.address)"
        } else {
            window.title = "Redis Console"
        }
    }
}
