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

    // MARK: - Shell History (Keychain-backed)

    private static let shellHistoryKeychainService = "com.redisconsole.shellHistory"

    private func shellHistoryKeychainAccount(for connection: RedisConnectionConfig) -> String {
        connection.id.uuidString
    }

    func loadShellHistory(for connection: RedisConnectionConfig) {
        // One-shot migration from UserDefaults to Keychain
        let account = shellHistoryKeychainAccount(for: connection)
        try? KeychainStore.migrateFromUserDefaults(
            [ShellHistoryEntry].self,
            userDefaultsKey: Self.shellHistoryKeyPrefix + connection.id.uuidString,
            service: Self.shellHistoryKeychainService,
            account: account
        )

        guard
            let decoded = try? KeychainStore.load(
                [ShellHistoryEntry].self,
                service: Self.shellHistoryKeychainService,
                account: account
            )
        else {
            shellHistory = []
            return
        }
        shellHistory = Array(decoded.suffix(shellHistoryLimit))
    }

    private func saveShellHistory(for connection: RedisConnectionConfig) {
        let limitedHistory = Array(shellHistory.suffix(shellHistoryLimit))
        shellHistory = limitedHistory
        let account = shellHistoryKeychainAccount(for: connection)
        let service = Self.shellHistoryKeychainService
        Task.detached {
            try? KeychainStore.store(
                limitedHistory,
                service: service,
                account: account
            )
        }
    }

    func appendShellHistory(_ entry: ShellHistoryEntry) {
        shellHistory.append(entry)
        if shellHistory.count > shellHistoryLimit {
            shellHistory.removeFirst(shellHistory.count - shellHistoryLimit)
        }
        guard let selectedConnection else { return }
        saveShellHistory(for: selectedConnection)
    }

    func deleteShellHistoryEntry(_ entry: ShellHistoryEntry) {
        shellHistory.removeAll { $0.id == entry.id }
        guard let selectedConnection else { return }
        saveShellHistory(for: selectedConnection)
    }

    func clearShellHistory() {
        shellHistory = []
        guard let selectedConnection else { return }
        saveShellHistory(for: selectedConnection)
    }
}
