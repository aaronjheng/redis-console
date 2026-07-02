import SwiftUI

// MARK: - Welcome View

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: AppTheme.spacingLarge) {
            Image(systemName: "server.rack")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Redis Console")
                .font(.title)
            Text("Select a connection or click + to add one")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
