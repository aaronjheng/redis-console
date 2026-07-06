import AppKit

enum AppAppearance: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    private static let userDefaultsKey = "com.redisconsole.appearance"

    var name: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    static var current: AppAppearance {
        let raw = UserDefaults.standard.integer(forKey: userDefaultsKey)
        return AppAppearance(rawValue: raw) ?? .system
    }

    @MainActor
    func apply() {
        UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey)
    }

    @MainActor
    func applyToWindow(_ window: NSWindow) {
        switch self {
        case .system:
            window.appearance = nil
        case .light:
            window.appearance = NSAppearance(named: .aqua)
        case .dark:
            window.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
