import Foundation
import Security

/// Store-account secrets — OAuth refresh tokens, mostly — in the login keychain.
///
/// Why the keychain and not a file under Application Support: a refresh token is a long-lived
/// credential for someone's game library. A plist in a user-readable directory would be a
/// credential-at-rest bug, and Cellar asks people to sign in to their real accounts. Access is
/// scoped by service name, and the item is `WhenUnlockedThisDeviceOnly` so it is never carried to
/// another Mac by a keychain sync or a Time Machine restore.
public enum Keychain {
    /// One namespace per store, so signing out of GOG never touches Steam.
    public static func service(for store: GameStore) -> String { "it.clercq.cellar.\(store.rawValue)" }

    /// Write (or replace) a secret. An empty string means "remove", so a caller can sign out by
    /// writing nothing rather than by knowing about deletion.
    public static func set(_ value: String, account: String, store: GameStore) throws {
        guard !value.isEmpty else { try remove(account: account, store: store); return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: store),
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw error(addStatus, "save") }
        } else if status != errSecSuccess {
            throw error(status, "update")
        }
    }

    public static func get(account: String, store: GameStore) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: store),
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func remove(account: String, store: GameStore) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: store),
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status, "remove") }
    }

    /// Errors point at the fix: a keychain denial is almost always the player having clicked "Deny"
    /// on the access prompt, which no amount of retrying inside Cellar will resolve.
    private static func error(_ status: OSStatus, _ verb: String) -> CellarError {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return CellarError.ioFailure(
            "Could not \(verb) the sign-in token in your keychain: \(detail). If you denied the keychain prompt, allow Cellar in Keychain Access and sign in again.")
    }
}
