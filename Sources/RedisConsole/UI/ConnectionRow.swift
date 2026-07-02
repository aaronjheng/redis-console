import AppKit
import SwiftUI

// MARK: - Connection Row

struct ConnectionRow: View {
    let config: RedisConnectionConfig
    let isConnected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXSmall) {
            HStack(spacing: AppTheme.spacingSmall) {
                Text(config.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: AppTheme.spacing)
                if config.environment != .unspecified {
                    Badge(
                        text: config.environment.rawValue,
                        systemImage: config.environment.icon,
                        foregroundColor: config.environment.badgeForegroundColor,
                        backgroundColor: config.environment.badgeBackgroundColor
                    )
                    .help("Environment: \(config.environment.rawValue)")
                }
                Badge(
                    text: config.mode.title,
                    foregroundColor: config.mode.badgeForegroundColor,
                    backgroundColor: config.mode.badgeBackgroundColor
                )
                .help("Connection mode: \(config.mode.title)")
            }
            Text(config.address)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, AppTheme.spacingSmall)
        .contentShape(Rectangle())
    }
}

// MARK: - Double Click Handler

struct DoubleClickHandler: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DoubleClickView {
        let view = DoubleClickView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: DoubleClickView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }
}

class DoubleClickView: NSView {
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }
}
