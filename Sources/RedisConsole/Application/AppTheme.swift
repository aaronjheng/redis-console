import SwiftUI

// MARK: - Theme Constants

enum AppTheme {
    static let spacing: CGFloat = 8
    static let spacingSmall: CGFloat = 4
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
    static let badgeMinWidth: CGFloat = 42

    static let sidebarMinWidth: CGFloat = 220
    static let sidebarMaxWidth: CGFloat = 280
    static let detailPanelMinWidth: CGFloat = 400

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
        .lineLimit(1)
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
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(minWidth: AppTheme.badgeMinWidth)
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
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous))
            .fixedSize(horizontal: true, vertical: false)
        }
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
