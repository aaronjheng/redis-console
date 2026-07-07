import SwiftUI

struct WorkspaceFooterBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .font(.caption)
        .controlSize(.regular)
        .imageScale(.medium)
        .padding(.horizontal, 8)
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

struct StatusFooterView: View {
    let countText: String
    var sizeText: String?

    init(countText: String, sizeText: String? = nil) {
        self.countText = countText
        self.sizeText = sizeText
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(countText)
            if let sizeText {
                Text("\u{00B7}")
                Text(sizeText)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

struct Badge: View {
    let text: String
    var systemImage: String?
    var foregroundColor: Color = .secondary
    var backgroundColor: Color = Color.secondary.opacity(0.12)
    var isLoading: Bool = false

    var body: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(minWidth: 42)
        } else {
            HStack(spacing: 2) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(text)
            }
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct ErrorBanner: View {
    enum Severity {
        case error
        case warning

        var icon: String { "exclamationmark.triangle.fill" }
        var color: Color {
            switch self {
            case .error: .red
            case .warning: .orange
            }
        }
        var background: Color { color.opacity(0.12) }
    }

    let message: String
    var severity: Severity = .error
    var dismissAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: severity.icon)
                .foregroundStyle(severity.color)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(severity == .warning ? .primary : severity.color)
                .lineLimit(2)
            Spacer()
            if let dismissAction {
                Button("Dismiss", systemImage: "xmark") {
                    dismissAction()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(severity.background)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct LoadingState: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct DeleteIconButton: View {
    let action: () -> Void
    var helpText: String?

    init(action: @escaping () -> Void, helpText: String? = nil) {
        self.action = action
        self.helpText = helpText
    }

    var body: some View {
        Button("Delete", systemImage: "trash", role: .destructive) {
            action()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help(helpText ?? "Delete")
    }
}

struct RefreshControl: View {
    @Binding var autoRefreshInterval: TimeInterval
    let isLoading: Bool
    let intervals: [TimeInterval]
    let onRefresh: () -> Void

    private var isAutoRefreshEnabled: Bool {
        autoRefreshInterval > 0
    }

    private static func intervalTitle(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        if totalSeconds.isMultiple(of: 60) {
            return "\(totalSeconds / 60)m"
        }
        return "\(totalSeconds)s"
    }

    @State private var isRefreshHovering = false
    @State private var isMenuHovering = false

    var body: some View {
        HStack(spacing: 0) {
            refreshButton
            separator
            intervalMenu
        }
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .opacity(isLoading ? 0.5 : 1)
    }

    private var refreshButton: some View {
        Button {
            onRefresh()
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
                .font(.caption)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .background(
                    isRefreshHovering && !isLoading
                        ? Color.primary.opacity(0.08)
                        : Color.clear
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 6,
                        bottomLeadingRadius: 6,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { isRefreshHovering = $0 }
        .help("Refresh")
    }

    private var separator: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 0.5, height: 14)
    }

    private var intervalMenu: some View {
        Menu {
            Button {
                autoRefreshInterval = 0
            } label: {
                menuItemLabel(text: "Off", checked: !isAutoRefreshEnabled)
            }
            Divider()
            ForEach(intervals, id: \.self) { interval in
                Button {
                    autoRefreshInterval = interval
                } label: {
                    menuItemLabel(
                        text: Self.intervalTitle(interval),
                        checked: isAutoRefreshEnabled && autoRefreshInterval == interval
                    )
                }
            }
        } label: {
            HStack(spacing: 0) {
                if isAutoRefreshEnabled {
                    Text(Self.intervalTitle(autoRefreshInterval))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 6)
                } else {
                    Color.clear.frame(width: 18, height: 22)
                }
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .background(
                isMenuHovering && !isLoading
                    ? Color.primary.opacity(0.08)
                    : Color.clear
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 6,
                    topTrailingRadius: 6,
                    style: .continuous
                )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .disabled(isLoading)
        .onHover { isMenuHovering = $0 }
        .help(isAutoRefreshEnabled ? "Auto refresh every \(Self.intervalTitle(autoRefreshInterval))" : "Auto refresh off")
    }

    private func menuItemLabel(text: String, checked: Bool) -> some View {
        Text(checked ? "\(text)  \u{2713}" : text)
    }
}
