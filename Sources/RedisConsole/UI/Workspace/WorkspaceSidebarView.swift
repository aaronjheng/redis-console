import SwiftUI

// MARK: - Workspace Sidebar

struct WorkspaceSidebarView: View {
    @Environment(TabState.self) private var tab

    var body: some View {
        @Bindable var tab = tab

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if let selectedConnection = tab.selectedConnection {
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

            List(selection: $tab.currentSection) {
                ForEach(WorkspaceSection.allCases, id: \.self) { view in
                    Label(view.rawValue, systemImage: view.icon)
                        .tag(view)
                }
            }
            .listStyle(.sidebar)
            .flatSidebarBackground()

            Divider()

            PanelFooterBar {
                Button(role: .destructive) {
                    tab.disconnect()
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
