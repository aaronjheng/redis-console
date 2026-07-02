import SwiftUI

// MARK: - Connecting View

struct ConnectingView: View {
    @Environment(ConnectionState.self) private var conn
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: AppTheme.spacingXLarge) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 4)
                    .frame(width: 60, height: 60)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(isPulsing ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isPulsing)
            }
            .onAppear { isPulsing = true }

            if let pending = conn.pendingConnection {
                Text("Connecting to \(pending.name)")
                    .font(.title3)
                    .bold()
                Text(pending.address)
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
            Button("Cancel") { conn.cancelConnection() }
                .buttonStyle(.bordered)
                .padding(.top, AppTheme.spacing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
