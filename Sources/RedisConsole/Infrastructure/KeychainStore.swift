import Foundation
import Security

// MARK: - Keychain Store

/// A lightweight Codable wrapper around the macOS Keychain (Security framework).
/// Data is stored as a generic password item, protected by the device passcode
/// and unavailable when locked.
enum KeychainStore {

    // MARK: - Public API

    /// Stores a `Codable` value as a generic password item.
    static func store<T: Encodable>(_ value: T, service: String, account: String) throws {
        let data = try JSONEncoder().encode(value)
        try store(data: data, service: service, account: account)
    }

    /// Loads and decodes a `Codable` value from the Keychain.
    /// Returns `nil` if no item exists for the given service/account pair.
    static func load<T: Decodable>(_ type: T.Type, service: String, account: String) throws -> T? {
        guard let data = try loadData(service: service, account: account) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    /// Deletes a Keychain item, or does nothing if it does not exist.
    static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }

    // MARK: - Migration Helpers

    /// Migrates data from `UserDefaults` to the Keychain and removes the
    /// UserDefaults key. This is a one-shot migration; subsequent calls are
    /// no-ops once the Keychain already has data.
    static func migrateFromUserDefaults<T: Codable>(
        _ type: T.Type,
        userDefaultsKey: String,
        service: String,
        account: String
    ) throws {
        // Skip if already migrated
        if (try? loadData(service: service, account: account)) != nil { return }

        guard
            let data = UserDefaults.standard.data(forKey: userDefaultsKey),
            let decoded = try? JSONDecoder().decode(type, from: data)
        else { return }

        try store(decoded, service: service, account: account)
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    // MARK: - Private

    private static func store(data: Data, service: String, account: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        // Delete existing item first (upsert semantics)
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    private static func loadData(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }

        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status: status)
        }

        return result as? Data
    }
}

// MARK: - Errors

enum KeychainError: Error, CustomStringConvertible {
    case saveFailed(status: OSStatus)
    case loadFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)

    var description: String {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed (OSStatus \(status))"
        case .loadFailed(let status):
            return "Keychain load failed (OSStatus \(status))"
        case .deleteFailed(let status):
            return "Keychain delete failed (OSStatus \(status))"
        }
    }
}
