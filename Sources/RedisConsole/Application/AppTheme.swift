import SwiftUI

// MARK: - Theme Constants

enum AppTheme {
    static let spacingXSmall: CGFloat = 2
    static let spacingSmall: CGFloat = 4
    static let spacingSmallMedium: CGFloat = 6
    static let spacing: CGFloat = 8
    static let spacingMedium: CGFloat = 10
    static let spacingLargeMedium: CGFloat = 12
    static let spacingLarge: CGFloat = 16
    static let spacingXLarge: CGFloat = 20

    static let cornerRadiusSmall: CGFloat = 4
    static let cornerRadiusMedium: CGFloat = 6
    static let cornerRadiusLarge: CGFloat = 8

    static let tabBarHeight: CGFloat = 32
    static let workspaceFooterHeight: CGFloat = 34
    static let refreshControlHeight: CGFloat = 22
    static let refreshButtonWidth: CGFloat = 26
    static let refreshButtonHeight: CGFloat = 22
    static let refreshSeparatorWidth: CGFloat = 0.5
    static let refreshSeparatorHeight: CGFloat = 14
    static let refreshMenuPlaceholderWidth: CGFloat = 18
    static let badgeMinWidth: CGFloat = 42

    static let sidebarMinWidth: CGFloat = 220
    static let sidebarMaxWidth: CGFloat = 280
    static let detailPanelMinWidth: CGFloat = 400

    static let hoverHighlight: Color = Color.primary.opacity(0.08)
    static let selectedRowBackground: Color = Color.accentColor.opacity(0.14)

    // MARK: - Background Colors
    static var sidebarBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var controlBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var textEditorBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }
}

// MARK: - Domain Colors

enum DomainColor {
    static let statusSuccess: Color = .green
    static let statusWarning: Color = .orange
    static let statusError: Color = .red
    static let statusInfo: Color = .blue

    static let typeString: Color = .blue
    static let typeList: Color = .green
    static let typeHash: Color = .orange
    static let typeSet: Color = .purple
    static let typeZSet: Color = .pink
    static let typeStream: Color = .secondary
    static let typeUnknown: Color = .secondary

    static let jsonKey: Color = .teal
    static let jsonString: Color = .green
    static let jsonNumber: Color = .blue
    static let jsonBoolean: Color = .orange
    static let jsonNull: Color = .red

    static let shellCommand: Color = .purple
    static let shellString: Color = .green
    static let shellNumber: Color = .orange
    static let shellComment: Color = .secondary

    static func expirationColor(_ label: String) -> Color {
        switch label {
        case "< 1h": return .red
        case "1-6h": return .orange
        case "6-24h": return .yellow
        case "1-7d": return .blue
        case "7-30d": return .green
        case "> 30d": return .secondary
        case "No expiry": return .gray
        default: return .secondary
        }
    }

    static func typeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "string": return typeString
        case "list": return typeList
        case "hash": return typeHash
        case "set": return typeSet
        case "zset": return typeZSet
        case "stream": return typeStream
        default: return typeUnknown
        }
    }
}

// MARK: - Reusable Status Footer

struct WorkspaceFooterBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: AppTheme.spacing) {
            content
        }
        .font(.caption)
        .controlSize(.regular)
        .imageScale(.medium)
        .padding(.horizontal, AppTheme.spacing)
        .frame(height: AppTheme.workspaceFooterHeight)
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
        HStack(spacing: AppTheme.spacingSmall) {
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

// MARK: - Reusable Badge

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
                .padding(.horizontal, AppTheme.spacingSmallMedium)
                .padding(.vertical, AppTheme.spacingXSmall)
                .frame(minWidth: AppTheme.badgeMinWidth)
        } else {
            HStack(spacing: AppTheme.spacingXSmall) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(text)
            }
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, AppTheme.spacingSmallMedium)
            .padding(.vertical, AppTheme.spacingXSmall)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous))
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    enum Severity {
        case error
        case warning

        var icon: String { "exclamationmark.triangle.fill" }
        var color: Color {
            switch self {
            case .error: DomainColor.statusError
            case .warning: DomainColor.statusWarning
            }
        }
        var background: Color { color.opacity(0.12) }
    }

    let message: String
    var severity: Severity = .error
    var dismissAction: (() -> Void)?

    var body: some View {
        HStack(spacing: AppTheme.spacing) {
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
        .padding(.horizontal, AppTheme.spacing)
        .padding(.vertical, AppTheme.spacingSmallMedium)
        .background(severity.background)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
    }
}

// MARK: - Loading State

struct LoadingState: View {
    let message: String

    var body: some View {
        VStack(spacing: AppTheme.spacing) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(AppTheme.spacingLarge)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(AppTheme.spacingLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge))
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

// MARK: - Refresh Control

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
        .frame(height: AppTheme.refreshControlHeight)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
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
                .frame(width: AppTheme.refreshButtonWidth, height: AppTheme.refreshButtonHeight)
                .contentShape(Rectangle())
                .background(
                    isRefreshHovering && !isLoading
                        ? AppTheme.hoverHighlight
                        : Color.clear
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: AppTheme.cornerRadiusMedium,
                        bottomLeadingRadius: AppTheme.cornerRadiusMedium,
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
            .frame(width: AppTheme.refreshSeparatorWidth, height: AppTheme.refreshSeparatorHeight)
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
                        .padding(.horizontal, AppTheme.spacingSmallMedium)
                } else {
                    Color.clear.frame(width: AppTheme.refreshMenuPlaceholderWidth, height: AppTheme.refreshControlHeight)
                }
            }
            .frame(height: AppTheme.refreshControlHeight)
            .contentShape(Rectangle())
            .background(
                isMenuHovering && !isLoading
                    ? AppTheme.hoverHighlight
                    : Color.clear
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: AppTheme.cornerRadiusMedium,
                    topTrailingRadius: AppTheme.cornerRadiusMedium,
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
