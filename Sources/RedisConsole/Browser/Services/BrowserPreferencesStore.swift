import Foundation

// MARK: - Browser Preferences Store

/// UserDefaults-backed gateway for browser preferences.
///
/// Owns the storage key, the schema version, and the corrupt-blob policy,
/// so `TabState` only maps between this DTO and its live properties.
enum BrowserPreferencesStore {
    struct Preferences: Codable {
        var version: Int
        var keyTypeFilter: String
        var isNamespaceGroupingEnabled: Bool
        var stringValueFormat: StringValueFormat
        var namespaceSeparator: String

        /// `version` is storage metadata: `save()` always stamps the current
        /// schema version, so callers never set it.
        init(
            keyTypeFilter: String,
            isNamespaceGroupingEnabled: Bool,
            stringValueFormat: StringValueFormat,
            namespaceSeparator: String
        ) {
            self.version = currentVersion
            self.keyTypeFilter = keyTypeFilter
            self.isNamespaceGroupingEnabled = isNamespaceGroupingEnabled
            self.stringValueFormat = stringValueFormat
            self.namespaceSeparator = namespaceSeparator
        }
    }

    private static let key = "com.redisconsole.browserPreferences"
    private static let currentVersion = 2

    /// Returns `nil` when nothing is stored. Corrupt or future-version blobs
    /// are dropped once (never silently reset on every launch) and read as
    /// `nil` so defaults apply until the next save.
    static func load() -> Preferences? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        guard let preferences = try? JSONDecoder().decode(Preferences.self, from: data),
            preferences.version <= currentVersion
        else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        return preferences
    }

    static func save(_ preferences: Preferences) {
        var stamped = preferences
        stamped.version = currentVersion
        guard let data = try? JSONEncoder().encode(stamped) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
