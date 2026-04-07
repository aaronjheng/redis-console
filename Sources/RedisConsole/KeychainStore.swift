import Foundation
import Security

enum KeychainStore {
    private static let service = "redis.console"

    @discardableResult
    static func setPassword(_ password: String, account: String) -> Bool {
        if password.isEmpty {
            deletePassword(account: account)
            return true
        }
        guard let encoded = password.data(using: .utf8) else {
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [
            kSecValueData as String: encoded,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            logStatus("setPassword update failed", status: updateStatus, account: account)
            return false
        }

        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: encoded,
        ]
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        }

        // Resolve conflicts from previously stored non-DataProtection entries.
        if addStatus == errSecDuplicateItem {
            let standardQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(standardQuery as CFDictionary)
            let retryStatus = SecItemAdd(item as CFDictionary, nil)
            if retryStatus != errSecSuccess {
                logStatus("setPassword retry add failed", status: retryStatus, account: account)
            }
            return retryStatus == errSecSuccess
        }

        logStatus("setPassword add failed", status: addStatus, account: account)
        return false
    }

    static func getPassword(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logStatus("getPassword failed", status: status, account: account)
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            logStatus("deletePassword failed", status: status, account: account)
        }

        // Cleanup potential pre-existing standard keychain duplicates.
        let standardQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let standardStatus = SecItemDelete(standardQuery as CFDictionary)
        if standardStatus != errSecSuccess, standardStatus != errSecItemNotFound {
            logStatus("deletePassword standard cleanup failed", status: standardStatus, account: account)
        }
    }

    private static func logStatus(_ action: String, status: OSStatus, account: String) {
        let statusText = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
        AppLogger.error("\(action) account=\(account) status=\(status) message=\(statusText)", category: "Keychain")
    }
}
