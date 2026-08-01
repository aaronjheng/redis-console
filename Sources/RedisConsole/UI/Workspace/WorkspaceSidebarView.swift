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
                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
                            Text(selectedConnection.name)
                                .font(.title3)
                                .fontWeight(.bold)
                                .lineLimit(1)
                            Spacer(minLength: AppSpacing.small)
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
                    .padding(AppSpacing.small)
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
