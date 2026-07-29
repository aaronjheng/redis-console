import AppKit
import SwiftUI

// MARK: - Welcome View

struct WelcomeView: View {
    @Environment(ConnectionState.self) private var conn
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: AppSpacing.xLarge) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)

            VStack(spacing: AppSpacing.small) {
                Text("Redis Console")
                    .font(.largeTitle.weight(.semibold))
                Text("Connect to a Redis database to browse keys, run commands, and monitor performance.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            HStack(spacing: AppSpacing.medium) {
                Button {
                    conn.selectedConnection = nil
                    conn.rightPanel = .newConnection
                } label: {
                    Label("New Connection", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    ConnectionTransfer.importConfigurations(store: store)
                } label: {
                    Label("Import Connections", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Text("Tip: Double-click a connection in the sidebar to connect.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
