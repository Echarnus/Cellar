import CellarDomain
import Foundation
import Security

/// Store-account secrets — OAuth refresh tokens, mostly — in the login keychain.
///
/// Why the keychain and not a file under Application Support: a refresh token is a long-lived
/// credential for someone's game library. A plist in a user-readable directory would be a
/// credential-at-rest bug (OWASP MASVS-STORAGE-1), and Cellar asks people to sign in to their real
/// accounts. Access is scoped by service name, and the item is `WhenUnlockedThisDeviceOnly` — the
/// least permissive class that still works for a game launcher — so it is never carried to another
/// Mac by a keychain sync or a Time Machine restore.
///
/// **Reading the secret is the CLI's job.** On the login (file-based) keychain an item trusts the
/// binary that created it, and the app and the CLI are different binaries: every read from the
/// other one is a keychain prompt, and a token copied into the GUI process for no reason. So the
/// app asks only `contains`, which reads attributes — never the secret, never a prompt — and leaves
/// everything that needs the token to the `cellar` subprocess it already drives. Sharing one item
/// between the two properly (the data-protection keychain and a `keychain-access-groups`
/// entitlement) needs both signed with one Team ID, which waits on the Developer ID.
public enum Keychain {
    /// One namespace per store, so signing out of GOG never touches Steam.
    public static func service(for store: GameStore) -> String { "it.clercq.cellar.\(store.rawValue)" }

    /// Write (or replace) a secret. An empty string means "remove", so a caller can sign out by
    /// writing nothing rather than by knowing about deletion.
    public static func set(_ value: String, account: String, store: GameStore) throws {
        try set(value, account: account, service: service(for: store), label: label(for: store))
    }

    public static func get(account: String, store: GameStore) -> String? {
        get(account: account, service: service(for: store))
    }

    /// Whether an item exists, without reading it: attributes only, so no access prompt and no
    /// secret in this process. What "signed in?" should ask.
    public static func contains(account: String, store: GameStore) -> Bool {
        contains(account: account, service: service(for: store))
    }

    public static func remove(account: String, store: GameStore) throws {
        try remove(account: account, service: service(for: store))
    }

    /// Every item Cellar keeps for `store`, whatever account it was saved under — for a reset or an
    /// uninstall, which must not leave a credential behind because it was filed under an old name.
    public static func removeAll(store: GameStore) throws {
        try remove(account: nil, service: service(for: store))
    }

    /// What Keychain Access shows. Says whose and what, never the value.
    static func label(for store: GameStore) -> String { "Cellar — \(store.displayName) sign-in" }

    // MARK: - By service (the store-free core, so a test can use a throwaway service)

    /// The query that names an item. Never carries the value: a query is what gets logged by a
    /// debugger or echoed in an error, so it is built without one.
    static func query(account: String?, service: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let account { query[kSecAttrAccount as String] = account }
        return query
    }

    /// What gets written beside the value.
    static func attributes(value: String, label: String) -> [String: Any] {
        [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrLabel as String: label,
            kSecAttrDescription as String: "Cellar sign-in token",
        ]
    }

    static func set(_ value: String, account: String, service: String, label: String) throws {
        guard !value.isEmpty else { try remove(account: account, service: service); return }
        let query = query(account: account, service: service)
        let attributes = attributes(value: value, label: label)
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

    static func get(account: String, service: String) -> String? {
        var query = query(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func contains(account: String, service: String) -> Bool {
        var query = query(account: account, service: service)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    /// Remove one item, or — with no account — every item under `service`. `SecItemDelete` removes
    /// one match per call on some keychains and all of them on others, so it is repeated until
    /// nothing matches; the bound only stops a keychain that keeps answering "deleted" from
    /// spinning forever.
    static func remove(account: String?, service: String) throws {
        let query = query(account: account, service: service)
        for _ in 0..<64 {
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecItemNotFound { return }
            guard status == errSecSuccess else { throw error(status, "remove") }
        }
    }

    /// Errors point at the fix: a keychain denial is almost always the player having clicked "Deny"
    /// on the access prompt, which no amount of retrying inside Cellar will resolve. They name the
    /// operation, never the value.
    private static func error(_ status: OSStatus, _ verb: String) -> CellarError {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return CellarError.ioFailure(
            "Could not \(verb) the sign-in token in your keychain: \(detail). If you denied the keychain prompt, allow Cellar in Keychain Access and sign in again.")
    }
}
