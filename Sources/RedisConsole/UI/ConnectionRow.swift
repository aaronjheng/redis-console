import AppKit
import SwiftUI

// MARK: - Connection Row

struct ConnectionRow: View {
    let config: RedisConnectionConfig
    let isConnected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppTheme.spacingSmall) {
                Text(config.name)
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: AppTheme.spacing)
                ConnectionEnvironmentBadge(environment: config.environment)
                ConnectionModeBadge(mode: config.mode)
            }
            Text(config.address)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct ConnectionModeBadge: View {
    let mode: RedisConnectionMode

    var body: some View {
        Text(mode.title)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundStyle)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous))
            .fixedSize(horizontal: true, vertical: false)
            .help("Connection mode: \(mode.title)")
    }

    private var foregroundStyle: Color {
        switch mode {
        case .standalone: return .secondary
        case .cluster: return .accentColor
        }
    }

    private var backgroundStyle: Color {
        switch mode {
        case .standalone: return Color.secondary.opacity(0.12)
        case .cluster: return Color.accentColor.opacity(0.14)
        }
    }
}

struct ConnectionEnvironmentBadge: View {
    let environment: ConnectionEnvironment

    var body: some View {
        if environment != .unspecified {
            Label(environment.rawValue, systemImage: environment.icon)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(environment.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(environment.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous))
                .fixedSize(horizontal: true, vertical: false)
                .help("Environment: \(environment.rawValue)")
        }
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
