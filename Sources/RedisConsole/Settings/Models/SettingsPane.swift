import Foundation

// MARK: - Settings Pane

enum SettingsPane: Hashable, CaseIterable {
    case appearance

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        }
    }
}
