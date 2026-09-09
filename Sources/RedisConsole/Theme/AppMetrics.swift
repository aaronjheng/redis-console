import Foundation

/// Standard spacing, corner radius, and size constants.
///
/// Centralizing these values removes magic numbers and keeps the UI
/// visually consistent.
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
    /// Fixed width for leading form labels (e.g. Library / Function / Mode rows in dialogs)
    /// so their values stay left-aligned across rows.
    static let formLabelWidth: CGFloat = 68
    /// Compact width for short leading labels (e.g. Key / Type / Value rows in Add New Key sheet).
    /// Sized to fit the longest label ("Value") with a small margin.
    static let formLabelWidthCompact: CGFloat = 40
    static let footerHeight: CGFloat = 34
    /// Unified minimum height for panel toolbars/headers (Browser, Shell, Profiler, Slow Log, Analysis, Server Info).
    /// Applied as a `minHeight` so headers stay consistent while still growing to fit taller content.
    static let toolbarHeight: CGFloat = 44
    static let refreshControlHeight: CGFloat = 22
    static let refreshButtonWidth: CGFloat = 26
    static let refreshSeparatorHeight: CGFloat = 14
    /// Unified width for the small type/engine badge in key and library rows.
    static let typeBadgeWidth: CGFloat = 64
    /// Horizontal inset of the native sidebar selection rect, mirrored by
    /// `sidebarHoverWash` so hover matches selection geometry.
    static let sidebarSelectionInset: CGFloat = 10
    /// Height of a default rounded-border text field; `FilterField` icon
    /// buttons use it so their hover wash matches the field height.
    static let filterFieldHeight: CGFloat = 22
    /// Fixed width of the settings sidebar column.
    static let settingsSidebarWidth: CGFloat = 215
    /// Minimum width of the settings detail column.
    static let settingsDetailMinimumWidth: CGFloat = 420
}
