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
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(selectedConnection.name)
                                .font(.title3)
                                .fontWeight(.bold)
                                .lineLimit(1)
                            Spacer(minLength: 8)
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
