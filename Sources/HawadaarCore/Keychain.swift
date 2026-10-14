import Foundation
import Security

/// Stores the MirAIe username and password in the login Keychain.
public enum Keychain {
    private static let service = "Hawadaar.MirAIe"
    private static let account = "credentials"

    public static func save(username: String, password: String) {
        delete()
        guard let data = try? JSONSerialization.data(withJSONObject: ["username": username, "password": password]) else { return }
        SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                    kSecAttrAccount: account, kSecValueData: data] as CFDictionary, nil)
    }

    public static func load() -> (username: String, password: String)? {
        var result: AnyObject?
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                     kSecAttrAccount: account, kSecReturnData: true] as CFDictionary
        guard SecItemCopyMatching(query, &result) == errSecSuccess, let data = result as? Data,
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let username = fields["username"], let password = fields["password"] else { return nil }
        return (username, password)
    }

    public static func delete() {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary)
    }
}
