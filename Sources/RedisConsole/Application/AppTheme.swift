import SwiftUI

// MARK: - Theme Constants

enum AppTheme {
    static let spacing: CGFloat = 8
    static let spacingSmall: CGFloat = 4
    static let spacingLarge: CGFloat = 16
    static let spacingXLarge: CGFloat = 20

    static let cornerRadiusSmall: CGFloat = 4
    static let cornerRadiusMedium: CGFloat = 6

    static let tabBarHeight: CGFloat = 32
    static let workspaceFooterHeight: CGFloat = 34

    // MARK: - Background Colors
    static var sidebarBackground: Color {
        Color(nsColor: .controlBackgroundColor)
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
