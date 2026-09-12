import Foundation

/// Resolves the Application Support directory shared by `AppDatabase` and
/// `SettingsStore` (`~/Library/Application Support/Redis Console`).
enum AppSupportDirectory {
    static let current: URL? = {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("Redis Console", isDirectory: true)
    }()
}
