import Foundation

// MARK: - Browser Preferences Store

/// UserDefaults-backed gateway for browser preferences.
///
/// Owns the storage key, the schema version, and the corrupt-blob policy,
/// so `TabState` only maps between this DTO and its live properties.
enum BrowserPreferencesStore {
    struct Preferences: Codable {
        var keyTypeFilter: String
        var isNamespaceGroupingEnabled: Bool
        var stringValueFormat: StringValueFormat
        var namespaceSeparator: String
    }

    private static let key = "redis.console.browserPreferences"

    /// Returns `nil` when nothing is stored or the blob is corrupt, so
    /// defaults apply until the next save.
    static func load() -> Preferences? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Preferences.self, from: data)
    }

    static func save(_ preferences: Preferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
