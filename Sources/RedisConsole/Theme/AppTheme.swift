import SwiftUI

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
