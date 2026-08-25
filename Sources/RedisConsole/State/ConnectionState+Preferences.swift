import Foundation

extension ConnectionState {
    private struct BrowserPreferences: Codable {
        var keyTypeFilter: String
        var isNamespaceGroupingEnabled: Bool
        var stringValueFormat: StringValueFormat
    }

    func loadBrowserPreferences() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.browserPreferencesKey),
            let preferences = try? JSONDecoder().decode(BrowserPreferences.self, from: data)
        else {
            return
        }

        isRestoringPreferences = true
        defer { isRestoringPreferences = false }
        keyTypeFilter = preferences.keyTypeFilter
        isNamespaceGroupingEnabled = preferences.isNamespaceGroupingEnabled
        stringValueFormat = preferences.stringValueFormat
    }

    func saveBrowserPreferences() {
        let preferences = BrowserPreferences(
            keyTypeFilter: keyTypeFilter,
            isNamespaceGroupingEnabled: isNamespaceGroupingEnabled,
            stringValueFormat: stringValueFormat
        )
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: Self.browserPreferencesKey)
    }

    // MARK: - Shell History (SQLite-backed)

    /// URL of the JSON history file used before history moved to SQLite.
    private func legacyShellHistoryURL(for connection: RedisConnectionConfig) -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return
            appSupport
            .appendingPathComponent("redis.console", isDirectory: true)
            .appendingPathComponent("shell-history-\(connection.id.uuidString).json")
    }

    func loadShellHistory(for connection: RedisConnectionConfig) async {
        shellHistory = await ShellHistoryStore.shared.load(connectionID: connection.id, limit: shellHistoryLimit)
        if shellHistory.isEmpty {
            await migrateLegacyJSONFile(for: connection)
        }
    }

    /// One-shot migration from the JSON file used before history moved to
    /// SQLite. The file is removed after a successful import.
    private func migrateLegacyJSONFile(for connection: RedisConnectionConfig) async {
        guard
            let url = legacyShellHistoryURL(for: connection),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([ShellHistoryEntry].self, from: data)
        else {
            return
        }
        await ShellHistoryStore.shared.importEntries(decoded, connectionID: connection.id)
        try? FileManager.default.removeItem(at: url)
    }

    func appendShellHistory(_ entry: ShellHistoryEntry) {
        shellHistory.append(entry)
        if shellHistory.count > shellHistoryLimit {
            shellHistory.removeFirst(shellHistory.count - shellHistoryLimit)
        }
        guard let selectedConnection else { return }
        let connectionID = selectedConnection.id
        let limit = shellHistoryLimit
        Task {
            await ShellHistoryStore.shared.append(entry, connectionID: connectionID, limit: limit)
        }
    }

    func deleteShellHistoryEntry(_ entry: ShellHistoryEntry) {
        shellHistory.removeAll { $0.id == entry.id }
        guard let selectedConnection else { return }
        let connectionID = selectedConnection.id
        Task {
            await ShellHistoryStore.shared.delete(id: entry.id, connectionID: connectionID)
        }
    }

    func clearShellHistory() {
        shellHistory = []
        guard let selectedConnection else { return }
        let connectionID = selectedConnection.id
        Task {
            await ShellHistoryStore.shared.clear(connectionID: connectionID)
        }
    }
}
