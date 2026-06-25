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

// MARK: - Reusable Delete Button

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
