import Foundation

extension TabState {
    // MARK: - Browser Preferences

    func loadBrowserPreferences() {
        guard let preferences = BrowserPreferencesStore.load() else { return }
        isRestoringPreferences = true
        defer { isRestoringPreferences = false }
        keyTypeFilter = preferences.keyTypeFilter
        isNamespaceGroupingEnabled = preferences.isNamespaceGroupingEnabled
        stringValueFormat = preferences.stringValueFormat
        namespaceSeparator = preferences.namespaceSeparator
    }

    func saveBrowserPreferences() {
        BrowserPreferencesStore.save(
            BrowserPreferencesStore.Preferences(
                keyTypeFilter: keyTypeFilter,
                isNamespaceGroupingEnabled: isNamespaceGroupingEnabled,
                stringValueFormat: stringValueFormat,
                namespaceSeparator: namespaceSeparator
            )
        )
    }
}
