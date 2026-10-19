import Foundation
import Security

/// 密码存在系统钥匙串里（只在勾选“记住密码”时），用于登录失效时自动重新登录。
/// iOS 上放进 App Group 的钥匙串分组，Siri 意图和小组件也能用。
enum Keychain {
    private static let service = "YorkAC.password"

    private static func base(_ account: String, group: String?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let g = group { q[kSecAttrAccessGroup as String] = g }
        return q
    }

    private static var groups: [String?] {
        #if os(iOS)
        return [AppConfig.appGroup, nil]
        #else
        return [nil]
        #endif
    }

    static func save(_ value: String, account: String) {
        delete(account: account)
        for g in groups {
            var item = base(account, group: g)
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            if SecItemAdd(item as CFDictionary, nil) == errSecSuccess { return }
        }
    }

    static func load(account: String) -> String? {
        for g in groups {
            var query = base(account, group: g)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
               let data = out as? Data, let s = String(data: data, encoding: .utf8) {
                return s
            }
        }
        return nil
    }

    static func delete(account: String) {
        for g in groups { SecItemDelete(base(account, group: g) as CFDictionary) }
    }
}
