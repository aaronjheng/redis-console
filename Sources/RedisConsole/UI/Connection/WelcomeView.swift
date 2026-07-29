import SwiftUI

// MARK: - Welcome View

struct WelcomeView: View {
    var body: some View {
        ContentUnavailableView(
            "Redis Console",
            systemImage: "server.rack",
            description: Text("Select a connection or click + to add one")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
