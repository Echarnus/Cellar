import CellarDomain
import Foundation

/// Keeps Steam's refresh token in the keychain whenever DepotDownloader is not running (#82).
///
/// DepotDownloader keeps the token in its own `account.config`, and only reads it from there. So
/// the file has to exist while the tool runs — but not a moment longer. Around every run:
///
/// - **restore** (before): if the file is gone and the keychain holds it, the file is written back,
///   `0600`, where DepotDownloader left it;
/// - **seal** (after the *last* run ends): the file's bytes go into the keychain, are read back to
///   prove they landed, and only then is the file deleted.
///
/// Concurrency is real: the app and the CLI check ownership of a whole library side by side. So
/// every run holds a **lease** (a file named for its pid) for its whole life, taken and dropped under
/// one cross-process lock, and only the run that drops the last lease seals. A lease whose process
/// has died is ignored, so a killed `cellar` cannot keep the token on disk forever — the next run
/// that ends seals it.
///
/// Failure always leaves the token *usable*, never lost: a keychain that will not take the bytes
/// (locked, denied) leaves the file where it was (still `0600` and out of backups); a keychain that
/// will not give them back leaves the index saying who is signed in, and the warning in the log.
///
/// The app never reads the keychain item. It needs only *who* is signed in and whether that
/// session is one the bottle's client would accept, so a seal also writes a small index — account
/// names and the token's public claims (Steam ID, audience, expiry), never the token — to a `0600`
/// file beside Steam's sign-in record.
public enum SteamTokenVault {

    // MARK: - What is kept

    /// One store file as it was sealed: where it lived, and its bytes.
    struct Entry: Codable, Equatable {
        var path: String
        var data: Data
        var modified: Date
    }

    /// What the app may read without the keychain: who holds a token, and what that token says
    /// about itself in public. Never a token.
    struct Index: Codable, Equatable {
        struct Account: Codable, Equatable {
            var name: String
            var claims: SteamClientSession.Claims?
        }
        var accounts: [Account]
        var sealedAt: Date
    }

    /// Where the keychain half is kept. A seam so tests use memory, not the player's keychain.
    struct Storage {
        var save: (String) throws -> Void
        var load: () -> String?
        var exists: () -> Bool
        var remove: () throws -> Void

        static let keychainAccount = "depotdownloader-account-store"

        static let keychain = Storage(
            save: { try Keychain.set($0, account: keychainAccount, store: .steam) },
            load: { Keychain.get(account: keychainAccount, store: .steam) },
            exists: { Keychain.contains(account: keychainAccount, store: .steam) },
            remove: { try Keychain.remove(account: keychainAccount, store: .steam) })
    }

    nonisolated(unsafe) static var storage = Storage.keychain

    /// On, unless switched off with `CELLAR_STEAM_TOKEN_VAULT=0`. Off by default for a relocated
    /// Cellar (`CELLAR_HOME`): a test or a throwaway install must not move the player's real token
    /// into the keychain behind an index it keeps somewhere else.
    static var isEnabled: Bool {
        if let forced = forcedEnabled { return forced }
        switch ProcessInfo.processInfo.environment["CELLAR_STEAM_TOKEN_VAULT"]?.lowercased() {
        case "0", "off", "false", "no": return false
        case "1", "on", "true", "yes":  return true
        default:                        return !Reset.isRelocated
        }
    }

    /// Set by tests, which run relocated and use memory for `storage`.
    nonisolated(unsafe) static var forcedEnabled: Bool?

    static var indexFile: URL { indexFileOverride ?? Paths.shared.appendingPathComponent("steam-token-index.json") }
    /// Set by tests, so an index written by one cannot change what another reads as signed in.
    nonisolated(unsafe) static var indexFileOverride: URL?
    static var leaseDirectory: URL { DepotTool.root.appendingPathComponent("runs", isDirectory: true) }
    static var lockFile: URL { DepotTool.root.appendingPathComponent(".token-vault.lock") }

    // MARK: - The index (what the app reads)

    static var index: Index? {
        guard let data = try? Data(contentsOf: indexFile) else { return nil }
        return try? JSONDecoder.cellar.decode(Index.self, from: data)
    }

    /// The sealed store as `DepotTool.storedAccounts` counts stores: names, and when it was sealed.
    static var sealedAccounts: (names: [String], modified: Date)? {
        index.map { ($0.accounts.map(\.name), $0.sealedAt) }
    }

    /// The public claims of the sealed token for `account` — enough to decide whether a bottle's
    /// client would accept it, without reading the token.
    static func claims(for account: String) -> SteamClientSession.Claims? {
        index?.accounts.first { $0.name.caseInsensitiveCompare(account) == .orderedSame }?.claims
    }

    // MARK: - The token (what only a DepotDownloader run, or a hand-over, reads)

    /// The sealed token for `account`, from the keychain. Nil when nothing is sealed.
    static func refreshToken(for account: String) -> String? {
        entries()?.sorted { $0.modified > $1.modified }
            .lazy.compactMap { DepotAccountStore.refreshToken(for: account, inCompressed: $0.data) }.first
    }

    static func entries() -> [Entry]? {
        guard let text = storage.load(), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder.cellar.decode([Entry].self, from: data)
    }

    // MARK: - Around a run

    /// Held for the whole of one DepotDownloader run. `end()` seals when it was the last one.
    final class Lease {
        let file: URL
        private var ended = false

        fileprivate init(file: URL) { self.file = file }

        func end() {
            guard !ended else { return }
            ended = true
            SteamTokenVault.withLock {
                try? FileManager.default.removeItem(at: file)
                guard SteamTokenVault.liveLeases().isEmpty else { return }
                SteamTokenVault.seal(files: DepotTool.storedSessionFiles)
            }
        }

        deinit { end() }
    }

    /// Before a run: take a lease, and put the token back where DepotDownloader looks for it.
    static func begin() -> Lease? {
        guard isEnabled else { return nil }
        return withLock {
            try? FileManager.default.createDirectory(at: leaseDirectory, withIntermediateDirectories: true)
            PrivateFiles.restrict(directory: leaseDirectory)
            let lease = leaseDirectory.appendingPathComponent("\(getpid())-\(UUID().uuidString)")
            FileManager.default.createFile(atPath: lease.path, contents: nil)
            restore(files: DepotTool.storedSessionFiles)
            return Lease(file: lease)
        }
    }

    /// Put the sealed files back. Files already on disk win — they were written after the seal (a
    /// run that was killed before it could seal), so they are the newer truth.
    ///
    /// The index goes once the files are back: while they are on disk *they* say who is signed in,
    /// and an index left beside them would keep naming an account Steam may revoke during this run.
    /// It stays when the keychain would not hand the token over, because the sign-in still exists.
    static func restore(files present: [URL]) {
        guard present.isEmpty else {
            try? FileManager.default.removeItem(at: indexFile)
            return
        }
        guard storage.exists() else {
            // Nothing sealed: an index without a keychain item names a session that is not there.
            try? FileManager.default.removeItem(at: indexFile)
            return
        }
        guard let entries = entries() else {
            CellarLog.warn(.account, "The keychain would not hand back the Steam sign-in, so this run "
                + "goes without it. If a keychain prompt was denied, allow Cellar in Keychain Access.")
            return
        }
        var restored = true
        for entry in entries {
            let url = URL(fileURLWithPath: entry.path)
            do {
                try PrivateFiles.write(entry.data, to: url)
                PrivateFiles.excludeFromBackup(url)
                try? FileManager.default.setAttributes([.modificationDate: entry.modified], ofItemAtPath: url.path)
            } catch {
                restored = false
            }
        }
        if restored { try? FileManager.default.removeItem(at: indexFile) }
    }

    /// Move the store files into the keychain. The files are deleted only once the keychain has
    /// given back exactly what was put in.
    static func seal(files: [URL], now: Date = Date()) {
        guard !files.isEmpty else { return }
        let entries = files.compactMap { url -> Entry? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? now
            return Entry(path: url.path, data: data, modified: modified)
        }
        guard entries.count == files.count,
              let payload = try? JSONEncoder.cellar.encode(entries),
              let text = String(data: payload, encoding: .utf8) else { return }
        do {
            try storage.save(text)
        } catch {
            CellarLog.warn(.account, "Kept the Steam sign-in in DepotDownloader's file (private, not "
                + "backed up): the keychain did not take it — \(CellarLog.describe(error))")
            return
        }
        guard storage.load() == text else {
            CellarLog.warn(.account, "Kept the Steam sign-in in DepotDownloader's file: the keychain "
                + "did not give back what was saved.")
            return
        }
        let index = Index(accounts: makeAccounts(entries), sealedAt: now)
        guard let indexData = try? JSONEncoder.cellar.encode(index),
              (try? PrivateFiles.write(indexData, to: indexFile)) != nil else { return }
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    static func makeAccounts(_ entries: [Entry]) -> [Index.Account] {
        var seen = Set<String>()
        var accounts: [Index.Account] = []
        for entry in entries.sorted(by: { $0.modified > $1.modified }) {
            for name in DepotAccountStore.accountNames(inCompressed: entry.data)
            where seen.insert(name.lowercased()).inserted {
                let token = DepotAccountStore.refreshToken(for: name, inCompressed: entry.data)
                accounts.append(Index.Account(name: name, claims: token.flatMap(SteamClientSession.claims(ofToken:))))
            }
        }
        return accounts
    }

    /// Sign-out and reset: the keychain item and the index, whatever state they are in.
    static func forget() throws {
        try? FileManager.default.removeItem(at: indexFile)
        // A relocated Cellar's sign-out is not the player's: the keychain item is the real one.
        guard isEnabled || !Reset.isRelocated else { return }
        try storage.remove()
    }

    /// Whether anything is sealed — what a reset lists, without reading the token.
    static var isSealed: Bool { storage.exists() || FileManager.default.fileExists(atPath: indexFile.path) }

    // MARK: - Leases and the lock

    /// Leases whose process is still alive. A dead one is removed as it is found.
    static func liveLeases() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: leaseDirectory.path)) ?? []
        return names.compactMap { name -> URL? in
            let url = leaseDirectory.appendingPathComponent(name)
            guard let pid = pid_t(name.split(separator: "-").first ?? ""), isAlive(pid) else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return url
        }
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    /// One Cellar process at a time, across the app and every CLI. `flock` is released by the
    /// kernel if the holder dies, so a crash can never leave the vault locked.
    static func withLock<T>(_ body: () -> T) -> T {
        try? FileManager.default.createDirectory(at: lockFile.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let fd = open(lockFile.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return body() }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        return body()
    }
}
