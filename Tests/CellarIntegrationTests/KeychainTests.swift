import Foundation
import Security
import Testing
@testable import CellarKit

/// Tier A: the real login keychain, through the code GOG's sign-in uses (issue #79).
///
/// The unit suite proves what Cellar *asks* the keychain for; this proves the keychain does it —
/// that a token goes in, is found without being read, comes back, is replaced rather than
/// duplicated, and is gone after a sign-out and after a reset. It uses a throwaway service, never
/// one of Cellar's, so it cannot touch the player's real sign-in.
///
/// Skipped — visibly, never as a pass — where the process has no usable keychain (a locked one, or
/// a CI host without a login keychain).
@Suite(.serialized, .enabled(if: KeychainProbe.available, "no usable login keychain here"))
struct KeychainTests {
    static var service: String { KeychainProbe.service }

    @Test("A token round-trips, is found without being read, and is replaced rather than duplicated")
    func roundTrip() throws {
        defer { try? Keychain.remove(account: nil, service: Self.service) }
        let account = "oauth-session"
        #expect(!Keychain.contains(account: account, service: Self.service))

        try Keychain.set("first-token", account: account, service: Self.service, label: "Cellar test")
        #expect(Keychain.contains(account: account, service: Self.service))
        #expect(Keychain.get(account: account, service: Self.service) == "first-token")

        try Keychain.set("second-token", account: account, service: Self.service, label: "Cellar test")
        #expect(Keychain.get(account: account, service: Self.service) == "second-token")
        #expect(Self.count(account: account) == 1, "an update, not a second item beside the first")
    }

    @Test("Writing nothing signs out, and removing twice is not an error")
    func emptyRemoves() throws {
        defer { try? Keychain.remove(account: nil, service: Self.service) }
        try Keychain.set("token", account: "a", service: Self.service, label: "Cellar test")
        try Keychain.set("", account: "a", service: Self.service, label: "Cellar test")
        #expect(!Keychain.contains(account: "a", service: Self.service))
        try Keychain.remove(account: "a", service: Self.service)
    }

    @Test("Removing everything for a store takes items filed under any account name")
    func removeAll() throws {
        for account in ["oauth-session", "legacy-name", "another"] {
            try Keychain.set("token-\(account)", account: account, service: Self.service, label: "Cellar test")
        }
        try Keychain.remove(account: nil, service: Self.service)
        for account in ["oauth-session", "legacy-name", "another"] {
            #expect(!Keychain.contains(account: account, service: Self.service), "\(account) survived")
        }
    }

    @Test("The saved item carries Cellar's label, and its value nowhere but the data")
    func savedAttributes() throws {
        defer { try? Keychain.remove(account: nil, service: Self.service) }
        try Keychain.set("secret-value-xyz", account: "a", service: Self.service, label: "Cellar — Test sign-in")
        var query = Keychain.query(account: "a", service: Self.service)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess)
        let attributes = try #require(item as? [String: Any])
        #expect(attributes[kSecAttrLabel as String] as? String == "Cellar — Test sign-in")
        for (key, value) in attributes {
            #expect(!"\(value)".contains("secret-value-xyz"), "\(key) exposes the token as an attribute")
        }
    }

    @Test("The Steam token store survives a real keychain seal and restore byte for byte (#82)")
    func steamVaultRoundTrip() throws {
        let service = Self.service + ".steam"
        let saved = SteamTokenVault.storage
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-vault-it-\(UUID().uuidString)", isDirectory: true)
        SteamTokenVault.storage = SteamTokenVault.Storage(
            save: { try Keychain.set($0, account: "store", service: service, label: "Cellar test vault") },
            load: { Keychain.get(account: "store", service: service) },
            exists: { Keychain.contains(account: "store", service: service) },
            remove: { try Keychain.remove(account: nil, service: service) })
        SteamTokenVault.indexFileOverride = dir.appendingPathComponent("index.json")
        defer {
            try? Keychain.remove(account: nil, service: service)
            SteamTokenVault.storage = saved
            SteamTokenVault.indexFileOverride = nil
            try? FileManager.default.removeItem(at: dir)
        }

        // Binary, like DepotDownloader's deflated protobuf: every byte value, several KB.
        let bytes = Data((0..<6000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let file = dir.appendingPathComponent("IsolatedStorage/x/account.config")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: file)

        SteamTokenVault.seal(files: [file])
        #expect(!FileManager.default.fileExists(atPath: file.path), "sealed: off the disk")
        #expect(Keychain.contains(account: "store", service: service))

        SteamTokenVault.restore(files: [])
        #expect(try Data(contentsOf: file) == bytes, "restored exactly")
        #expect(PrivateFiles.mode(of: file) == 0o600)
    }

    static func count(account: String) -> Int {
        var query = Keychain.query(account: account, service: service)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess else { return 0 }
        return (items as? [[String: Any]])?.count ?? 0
    }
}

/// Outside the suite: a suite's trait cannot refer to the suite's own members (the `@Suite` macro
/// would have to resolve itself first).
enum KeychainProbe {
    static let service = "it.clercq.cellar.tests.\(ProcessInfo.processInfo.processIdentifier)"

    /// Probe once: add and remove an item under a throwaway service.
    static let available: Bool = {
        let probe = "\(service).probe"
        do {
            try Keychain.set("probe", account: "probe", service: probe, label: "Cellar test probe")
            try Keychain.remove(account: nil, service: probe)
            return true
        } catch {
            return false
        }
    }()
}
