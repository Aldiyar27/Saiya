import Foundation
import Security

enum AIConfig {
    static let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    static let model = "gemini-3.1-flash-lite"

    static var apiKey: String { Keychain.get("geminiKey") ?? "" }
    static var isConfigured: Bool { !apiKey.isEmpty }
}

enum Keychain {
    static func set(_ value: String, for key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty else { return }
        var a = q
        a[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(a as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
