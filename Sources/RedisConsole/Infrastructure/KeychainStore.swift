import Foundation
import Security

enum KeychainStore {
    private static let service = "redis.console"
    private static let dataProtectionKeychain = true

    @discardableResult
    static func setPassword(_ password: String, account: String) -> Bool {
        if password.isEmpty {
            deletePassword(account: account)
            return true
        }
        guard let encoded = password.data(using: .utf8) else {
            AppLogger.error("setPassword failed to UTF-8 encode payload account=\(account)", category: "Keychain")
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: dataProtectionKeychain,
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
            kSecUseDataProtectionKeychain as String: dataProtectionKeychain,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: encoded,
        ]
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let retryUpdateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard retryUpdateStatus == errSecSuccess else {
                logStatus("setPassword retry update failed", status: retryUpdateStatus, account: account)
                return false
            }
            return true
        }
        guard addStatus == errSecSuccess else {
            logStatus("setPassword add failed", status: addStatus, account: account)
            return false
        }
        return true
    }

    static func getPassword(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: dataProtectionKeychain,
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
            kSecUseDataProtectionKeychain as String: dataProtectionKeychain,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            logStatus("deletePassword failed", status: status, account: account)
        }
    }

    private static func logStatus(_ action: String, status: OSStatus, account: String) {
        let statusText = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
        AppLogger.error("\(action) account=\(account) status=\(status) message=\(statusText)", category: "Keychain")
    }
}
