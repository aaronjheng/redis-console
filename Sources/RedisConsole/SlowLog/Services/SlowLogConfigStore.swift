import Foundation

// MARK: - Slow Log Config Store

/// UserDefaults-backed gateway for the per-connection slow-log view config.
///
/// Owns the key scheme (`com.redisconsole.slowlog.<connection-UUID>`, with a
/// `.default` fallback before any connection is selected) so `TabState` only
/// maps between this DTO and its live property.
enum SlowLogConfigStore {
    static func load(connectionID: UUID?) -> SlowLogConfig? {
        guard
            let data = UserDefaults.standard.data(forKey: key(connectionID: connectionID)),
            let config = try? JSONDecoder().decode(SlowLogConfig.self, from: data)
        else { return nil }
        return config
    }

    static func save(_ config: SlowLogConfig, connectionID: UUID?) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: key(connectionID: connectionID))
    }

    private static func key(connectionID: UUID?) -> String {
        guard let connectionID else { return "com.redisconsole.slowlog.default" }
        return "com.redisconsole.slowlog.\(connectionID.uuidString)"
    }
}
