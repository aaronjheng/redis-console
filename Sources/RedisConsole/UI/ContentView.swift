import AppKit
import SwiftUI

// MARK: - Tab Content View (per-tab)

struct TabContentView: View {
    @EnvironmentObject var conn: ConnectionState
    @EnvironmentObject var store: AppStore
    @State private var cachedRightPanel: RightPanel = .welcome

    var body: some View {
        HSplitView {
            TabSidebarView()
                .frame(minWidth: 220, maxWidth: 280)

            if conn.activeClient?.isConnected == true {
                switch conn.currentView {
                case .browser: BrowserView()
                case .shell: ShellView()
                case .profiler: ProfilerView()
                case .serverInfo: ServerInfoView()
                }
            } else if conn.isConnecting {
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
        .background(WindowTitleUpdater().environmentObject(conn))
        .onChange(of: conn.rightPanel) { _, newValue in
            cachedRightPanel = newValue
        }
        .onAppear {
            cachedRightPanel = conn.rightPanel
        }
    }
}

// MARK: - Window Title Updater

struct WindowTitleUpdater: NSViewRepresentable {
    @EnvironmentObject var conn: ConnectionState

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
