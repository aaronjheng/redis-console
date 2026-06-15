import Foundation

extension ConnectionState {
    private struct BrowserPreferences: Codable {
        var keyTypeFilter: String
        var isNamespaceGroupingEnabled: Bool
        var namespaceSeparator: String
        var stringValueFormat: StringValueFormat
    }

    func loadBrowserPreferences() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.browserPreferencesKey),
            let preferences = try? JSONDecoder().decode(BrowserPreferences.self, from: data)
        else {
            return
        }

        keyTypeFilter = preferences.keyTypeFilter
        isNamespaceGroupingEnabled = preferences.isNamespaceGroupingEnabled
        namespaceSeparator = normalizedNamespaceSeparator(preferences.namespaceSeparator)
        stringValueFormat = preferences.stringValueFormat
    }

    func saveBrowserPreferences() {
        let preferences = BrowserPreferences(
            keyTypeFilter: keyTypeFilter,
            isNamespaceGroupingEnabled: isNamespaceGroupingEnabled,
            namespaceSeparator: normalizedNamespaceSeparator(namespaceSeparator),
            stringValueFormat: stringValueFormat
        )
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: Self.browserPreferencesKey)
    }

    private func normalizedNamespaceSeparator(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return ":" }
        return String(first)
    }

    func updateNamespaceSeparator(_ value: String) {
        namespaceSeparator = normalizedNamespaceSeparator(value)
    }

    private func shellHistoryKey(for connection: RedisConnectionConfig) -> String {
        Self.shellHistoryKeyPrefix + connection.id.uuidString
    }

    func loadShellHistory(for connection: RedisConnectionConfig) {
        guard
            let data = UserDefaults.standard.data(forKey: shellHistoryKey(for: connection)),
            let decoded = try? JSONDecoder().decode([ShellHistoryEntry].self, from: data)
        else {
            shellHistory = []
            return
        }
        shellHistory = Array(decoded.suffix(shellHistoryLimit))
    }

    private func saveShellHistory(for connection: RedisConnectionConfig) {
        let limitedHistory = Array(shellHistory.suffix(shellHistoryLimit))
        shellHistory = limitedHistory
        guard let data = try? JSONEncoder().encode(limitedHistory) else { return }
        UserDefaults.standard.set(data, forKey: shellHistoryKey(for: connection))
    }

    func appendShellHistory(_ entry: ShellHistoryEntry) {
        shellHistory.append(entry)
        if shellHistory.count > shellHistoryLimit {
            shellHistory.removeFirst(shellHistory.count - shellHistoryLimit)
        }
        guard let selectedConnection else { return }
        saveShellHistory(for: selectedConnection)
    }
}
