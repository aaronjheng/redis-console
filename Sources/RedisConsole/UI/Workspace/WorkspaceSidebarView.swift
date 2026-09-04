import SwiftUI

// MARK: - Workspace Sidebar

struct WorkspaceSidebarView: View {
    @Environment(ConnectionState.self) private var conn

    /// Functions requires Redis 7.0+, so the entry is hidden on older servers.
    private var visibleViews: [AppView] {
        AppView.allCases.filter { $0 != .functions || conn.supportsFunctions }
    }

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
                            if selectedConnection.environment != .unspecified {
                                Badge(
                                    text: selectedConnection.environment.rawValue,
                                    systemImage: selectedConnection.environment.icon,
                                    foregroundColor: selectedConnection.environment.badgeForegroundColor,
                                    backgroundColor: selectedConnection.environment.badgeBackgroundColor
                                )
                                .help("Environment: \(selectedConnection.environment.rawValue)")
                            }
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
                ForEach(visibleViews, id: \.self) { view in
                    Label(view.rawValue, systemImage: view.icon)
                        .tag(view)
                }
            }
            .listStyle(.sidebar)
            .flatSidebarBackground()
            .onChange(of: conn.supportsFunctions) { _, supportsFunctions in
                if !supportsFunctions && conn.currentView == .functions {
                    conn.currentView = .browser
                }
            }

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
