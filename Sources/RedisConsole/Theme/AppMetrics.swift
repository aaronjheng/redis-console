import Foundation

/// Standard spacing, corner radius, and size constants.
///
/// Centralizing these values removes magic numbers and keeps the UI Inventory
/// screenshots visually consistent.
enum AppSpacing {
    static let xxSmall: CGFloat = 2
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 20
}

enum AppRadius {
    static let small: CGFloat = 4
    static let medium: CGFloat = 6
    static let large: CGFloat = 8
    static let pill: CGFloat = 9999
}

enum AppSize {
    static let productionConfirmWidth: CGFloat = 320
    static let ttlEditorWidth: CGFloat = 260
    static let formFieldWidth: CGFloat = 80
    static let footerHeight: CGFloat = 34
    static let refreshControlHeight: CGFloat = 22
    static let refreshButtonWidth: CGFloat = 26
    static let refreshSeparatorHeight: CGFloat = 14
}
