import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The Steam token lives in Cellar's own private file between DepotDownloader runs (#82), and never
/// in the keychain, whose prompts came back with every new build of `cellar` (#330).
///
/// These drive the vault with real DepotDownloader store bytes (`SteamSignInTests.store`), real
/// Steam-shaped tokens (`SteamClientSessionTests.jwt`) and real files in a scratch folder — only the
/// vault (and the keychain an older Cellar used) is replaced, by memory, so a test can never touch
/// the player's sign-in. The properties
/// pinned are the ones a bug here would cost: the token is never lost, never left on disk once the
/// keychain has it, and the app can still say who is signed in without reading it.
@Suite(.serialized)
struct SteamTokenVaultTests {

    /// The vault, in memory. Counts reads of the secret, so a test can prove a path never made one.
    /// `@unchecked Sendable` because the vault's storage closures are `@Sendable`: the suite is
    /// serialized, so only one test ever touches a `Memory` at a time.
    final class Memory: @unchecked Sendable {
        var value: String?
        var reads = 0
        var failSave = false
        var corruptOnLoad = false
        var denyLoad = false

        var storage: SteamTokenVault.Storage {
            SteamTokenVault.Storage(
                save: { [self] in
                    if failSave { throw CellarError.ioFailure("keychain locked") }
                    value = $0
                },
                load: { [self] in
                    reads += 1
                    if denyLoad { return nil }
                    return corruptOnLoad ? value.map { $0 + " " } : value
                },
                exists: { [self] in value != nil },
                remove: { [self] in value = nil })
        }
    }

    /// Point the vault at memory and a scratch index for the length of `body`.
    func withVault(_ body: (Memory, URL) throws -> Void) rethrows {
        let memory = Memory()
        let dir = TestHome.scratch("vault")
        let saved = SteamTokenVault.storage
        let savedLegacy = SteamTokenVault.legacy
        SteamTokenVault.storage = memory.storage
        SteamTokenVault.legacy = nil
        SteamTokenVault.indexFileOverride = dir.appendingPathComponent("steam-token-index.json")
        SteamTokenVault.storeFileOverride = dir.appendingPathComponent("steam-token-store.json")
        defer {
            SteamTokenVault.storage = saved
            SteamTokenVault.legacy = savedLegacy
            SteamTokenVault.indexFileOverride = nil
            SteamTokenVault.storeFileOverride = nil
            SteamTokenVault.forcedEnabled = nil
        }
        try body(memory, dir)
    }

    static let token = SteamClientSessionTests.jwt(sub: "76561197960265728")

    /// A DepotDownloader store on disk, where isolated storage would put it.
    func storeFile(in dir: URL, tokens: [(String, String)] = [("Player", token)]) throws -> URL {
        let file = dir.appendingPathComponent("IsolatedStorage/abc/def/account.config")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SteamSignInTests.store(tokens: tokens, guard: []).write(to: file)
        return file
    }

    // MARK: - Sealing

    @Test("Sealing moves the store into the vault and takes it off the disk")
    func sealMovesToKeychain() throws {
        try withVault { memory, dir in
            let file = try storeFile(in: dir)
            let bytes = try Data(contentsOf: file)
            SteamTokenVault.seal(files: [file])

            #expect(!FileManager.default.fileExists(atPath: file.path), "no copy left on disk")
            let entries = try #require(SteamTokenVault.entries())
            #expect(entries.map(\.data) == [bytes], "byte for byte what DepotDownloader wrote")
            #expect(entries.map(\.path) == [file.path])
            #expect(SteamTokenVault.refreshToken(for: "player") == Self.token)
        }
    }

    @Test("The index names who is signed in and what the token says, never the token")
    func indexHoldsNoToken() throws {
        try withVault { _, dir in
            SteamTokenVault.seal(files: [try storeFile(in: dir)])
            let index = try #require(SteamTokenVault.index)
            #expect(index.accounts.map(\.name) == ["Player"])
            #expect(index.accounts.first?.claims?.steamID == "76561197960265728")
            #expect(index.accounts.first?.claims?.isClientToken == true)

            let text = try String(contentsOf: SteamTokenVault.indexFile, encoding: .utf8)
            #expect(!text.contains(Self.token))
            for part in Self.token.split(separator: ".") { #expect(!text.contains(part)) }
            #expect(PrivateFiles.mode(of: SteamTokenVault.indexFile) == 0o600)
        }
    }

    @Test("Saying who is signed in never reads the vault — the app draws Accounts from this")
    func namesWithoutKeychainRead() throws {
        try withVault { memory, dir in
            SteamTokenVault.seal(files: [try storeFile(in: dir)])
            memory.reads = 0
            #expect(SteamTokenVault.sealedAccounts?.names == ["Player"])
            #expect(SteamTokenVault.claims(for: "PLAYER")?.steamID == "76561197960265728",
                    "Steam account names are case-insensitive")
            #expect(memory.reads == 0)
        }
    }

    @Test("A bottle's client is promised the session from the sealed claims alone")
    func readinessFromClaims() throws {
        try withVault { _, dir in
            SteamTokenVault.seal(files: [try storeFile(in: dir)])
            let snapshot = SteamClientSession.Snapshot(
                cellarAccount: "Player", token: nil, localConfig: nil, loginUsers: nil, config: nil,
                tokenClaims: SteamTokenVault.claims(for: "Player"))
            #expect(SteamClientSession.readiness(snapshot) == .canHandOver)

            let expired = SteamClientSession.Snapshot(
                cellarAccount: "Player", token: nil, localConfig: nil, loginUsers: nil, config: nil,
                tokenClaims: SteamClientSession.claims(ofToken: SteamClientSessionTests.jwt(expires: Date())))
            #expect(SteamClientSession.readiness(expired) == .unavailable(.tokenNotForClient))
        }
    }

    @Test("A keychain that will not take the token leaves the file where it is")
    func sealFailureKeepsFile() throws {
        try withVault { memory, dir in
            memory.failSave = true
            let file = try storeFile(in: dir)
            SteamTokenVault.seal(files: [file])
            #expect(FileManager.default.fileExists(atPath: file.path), "a sign-in is never lost to a locked keychain")
            #expect(SteamTokenVault.index == nil)
        }
    }

    @Test("A keychain that gives back something else leaves the file where it is")
    func sealVerifiesReadBack() throws {
        try withVault { memory, dir in
            memory.corruptOnLoad = true
            let file = try storeFile(in: dir)
            SteamTokenVault.seal(files: [file])
            #expect(FileManager.default.fileExists(atPath: file.path))
            #expect(SteamTokenVault.index == nil)
        }
    }

    // MARK: - Restoring

    @Test("Restoring writes the store back exactly, private, and drops the index")
    func restoreRoundTrip() throws {
        try withVault { _, dir in
            let file = try storeFile(in: dir)
            let bytes = try Data(contentsOf: file)
            SteamTokenVault.seal(files: [file])
            SteamTokenVault.restore(files: [])

            #expect(try Data(contentsOf: file) == bytes)
            #expect(PrivateFiles.mode(of: file) == 0o600)
            #expect(PrivateFiles.isExcludedFromBackup(file))
            #expect(SteamTokenVault.index == nil, "while the file is back, the file says who is signed in")
        }
    }

    @Test("A store already on disk is newer than the sealed one, and is not overwritten")
    func diskWins() throws {
        try withVault { _, dir in
            let file = try storeFile(in: dir)
            SteamTokenVault.seal(files: [file])
            let newer = try storeFile(in: dir, tokens: [("Player", "newer-token")])
            let newerBytes = try Data(contentsOf: newer)
            SteamTokenVault.restore(files: [newer])
            #expect(try Data(contentsOf: newer) == newerBytes)
        }
    }

    @Test("A keychain that refuses to hand the token back keeps the sign-in on record")
    func deniedRestoreKeepsIndex() throws {
        try withVault { memory, dir in
            SteamTokenVault.seal(files: [try storeFile(in: dir)])
            memory.denyLoad = true
            SteamTokenVault.restore(files: [])
            #expect(SteamTokenVault.index != nil, "denied is not signed out")
        }
    }

    @Test("An index with nothing in the keychain behind it is dropped")
    func orphanIndexDropped() throws {
        try withVault { memory, dir in
            SteamTokenVault.seal(files: [try storeFile(in: dir)])
            memory.value = nil
            SteamTokenVault.restore(files: [])
            #expect(SteamTokenVault.index == nil)
        }
    }

    @Test("Signing out empties the vault and the index")
    func forget() throws {
        try withVault { memory, dir in
            SteamTokenVault.forcedEnabled = true
            SteamTokenVault.seal(files: [try storeFile(in: dir)])
            try SteamTokenVault.forget()
            #expect(memory.value == nil)
            #expect(SteamTokenVault.index == nil)
            #expect(SteamTokenVault.refreshToken(for: "player") == nil)
        }
    }

    // MARK: - Runs side by side

    @Test("Only leases of living processes hold the token on disk; a crashed run's lease is cleared")
    func leases() throws {
        let dir = SteamTokenVault.leaseDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let mine = dir.appendingPathComponent("\(getpid())-\(UUID().uuidString)")
        let dead = dir.appendingPathComponent("99999999-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: mine.path, contents: nil)
        FileManager.default.createFile(atPath: dead.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: mine) }

        let live = SteamTokenVault.liveLeases()
        #expect(live.contains(mine))
        #expect(!live.contains(dead))
        #expect(!FileManager.default.fileExists(atPath: dead.path), "a dead run's lease is removed as it is found")
    }

    @Test("The lock is exclusive across holders, so two runs never seal and restore at once")
    func lockIsExclusive() async {
        let counter = Counter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    SteamTokenVault.withLock {
                        counter.enter()
                        usleep(2_000)
                        counter.leave()
                    }
                }
            }
        }
        #expect(counter.maximum == 1)
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var inside = 0
        private(set) var maximum = 0
        func enter() { lock.lock(); inside += 1; maximum = max(maximum, inside); lock.unlock() }
        func leave() { lock.lock(); inside -= 1; lock.unlock() }
    }

    @Test("A relocated Cellar leaves the player's real token alone unless asked")
    func offWhenRelocated() {
        #expect(Reset.isRelocated)
        #expect(!SteamTokenVault.isEnabled)
        #expect(SteamTokenVault.begin() == nil, "no lease, no restore, no seal")
    }

    // MARK: - No keychain (#330)

    /// The keychain an older Cellar sealed into, in memory. Counts every touch, because the bug was a
    /// prompt — and the only keychain call that can never prompt is one that is not made.
    final class LegacyMemory: @unchecked Sendable {
        var value: String?
        var readableWithoutPrompt = true
        var touches = 0

        var keychain: SteamTokenVault.LegacyKeychain {
            SteamTokenVault.LegacyKeychain(
                exists: { [self] in touches += 1; return value != nil },
                loadWithoutPrompt: { [self] in touches += 1; return readableWithoutPrompt ? value : nil },
                removeWithoutPrompt: { [self] in touches += 1; if readableWithoutPrompt { value = nil } })
        }
    }

    @Test("The vault is Cellar's own 0600 file, out of backups — not the keychain")
    func vaultIsAPrivateFile() throws {
        try withVault { _, dir in
            SteamTokenVault.storage = .file
            let file = try storeFile(in: dir)
            let bytes = try Data(contentsOf: file)
            SteamTokenVault.seal(files: [file])

            #expect(!FileManager.default.fileExists(atPath: file.path))
            #expect(PrivateFiles.mode(of: SteamTokenVault.storeFile) == 0o600)
            let excluded = try SteamTokenVault.storeFile.resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(excluded.isExcludedFromBackup == true)
            #expect(SteamTokenVault.refreshToken(for: "player") == Self.token)

            SteamTokenVault.restore(files: [])
            #expect(try Data(contentsOf: file) == bytes, "restored byte for byte")

            try SteamTokenVault.forget()
            #expect(!FileManager.default.fileExists(atPath: SteamTokenVault.storeFile.path))
        }
    }

    @Test("A token an older Cellar left in the keychain moves to the file once, without a prompt")
    func migratesOnce() throws {
        try withVault { memory, dir in
            let legacy = LegacyMemory()
            legacy.value = "sealed-by-0.6.4"
            SteamTokenVault.legacy = legacy.keychain

            SteamTokenVault.migrateFromKeychain()
            #expect(memory.value == "sealed-by-0.6.4", "moved into the vault")
            #expect(legacy.value == nil, "and taken out of the keychain")
            #expect(FileManager.default.fileExists(atPath: SteamTokenVault.migrationMarker.path))

            legacy.touches = 0
            SteamTokenVault.migrateFromKeychain()
            #expect(legacy.touches == 0, "looked at once, never again")
        }
    }

    @Test("A keychain item that would prompt is left alone, and asked about only once")
    func promptingItemIsLeftAlone() throws {
        try withVault { memory, dir in
            let legacy = LegacyMemory()
            legacy.value = "needs-a-prompt"
            legacy.readableWithoutPrompt = false
            SteamTokenVault.legacy = legacy.keychain

            SteamTokenVault.migrateFromKeychain()
            #expect(memory.value == nil, "nothing to restore: Steam asks for one fresh sign-in")
            legacy.touches = 0
            _ = SteamTokenVault.refreshToken(for: "Player")
            SteamTokenVault.migrateFromKeychain()
            #expect(legacy.touches == 0)
        }
    }

    @Test("A launch, a sign-in check and a DepotDownloader run never touch the keychain (#330)")
    func launchPathNeverTouchesKeychain() throws {
        try withVault { memory, dir in
            SteamTokenVault.forcedEnabled = true
            let legacy = LegacyMemory()
            SteamTokenVault.legacy = legacy.keychain
            SteamTokenVault.migrateFromKeychain()   // the one look, on the first run after updating
            legacy.touches = 0

            // What a run does around DepotDownloader (seal, restore, seal), and what a launch and
            // the Accounts panel read. `begin()`/`end()` are these plus a lease, and would search
            // the real isolated storage, so they are not called from a test.
            let file = try storeFile(in: dir)
            SteamTokenVault.seal(files: [file])
            _ = SteamTokenVault.sealedAccounts
            _ = SteamTokenVault.claims(for: "Player")
            _ = SteamTokenVault.refreshToken(for: "Player")
            SteamTokenVault.restore(files: [])
            SteamTokenVault.seal(files: [file])
            #expect(memory.value != nil)
            #expect(legacy.touches == 0)
        }
    }

    @Test("Steam's code calls only keychain functions that cannot prompt (#330)")
    func steamSourcesNeverReadTheKeychain() throws {
        // `get`/`set`/`remove` on the login keychain are what put "cellar wants to use your
        // confidential information" on screen whenever `cellar`'s signature changed. Steam's code,
        // the use cases, the CLI and the app may use none of them.
        let roots = [Repo.source("CellarData/Stores/Steam"), Repo.source("CellarData/UseCases"),
                     Repo.app.appendingPathComponent("src")]
        let forbidden = ["Keychain.get(", "Keychain.set(", "Keychain.remove(", "SecItemCopyMatching", "SecItemAdd"]
        var offenders: [String] = []
        for root in roots {
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
            #expect(!files.isEmpty, "\(root.path) has Swift sources")
            for file in files {
                let text = try String(contentsOf: file, encoding: .utf8)
                for call in forbidden where text.contains(call) {
                    offenders.append("\(file.lastPathComponent): \(call)")
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
