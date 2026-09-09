import Foundation

/// Putting the machine back to "Cellar has never run here".
///
/// Every piece of Cellar's state is derived — runners are downloaded, bottles are built, games are
/// re-downloadable from the store that sold them, and the sign-in is one scan away. So a clean
/// slate is a legitimate and occasionally necessary answer to "why is this bottle like that?",
/// which is why it is a command rather than a paragraph of `rm -rf` in a support thread.
///
/// It shows what it will delete, with sizes, **before** it deletes anything. Nothing here is
/// recoverable, and a 30 GB game re-download is a real cost — so the plan is the product, and the
/// deletion is the easy part.
public enum Reset {

    /// One removable thing, with what it costs to get back.
    public struct Item: Sendable {
        /// What is being removed. Not everything Cellar leaves behind is a file — GOG's sign-in is
        /// an OAuth token in the login keychain, and a reset that quietly skipped it would hand the
        /// next person at this Mac somebody else's library while printing "Clean slate."
        public enum Target: Sendable, Equatable {
            case path(URL)
            case storeCredentials(GameStore)
        }
        public let target: Target
        /// "Games and the Windows Steam client" — what the player is losing, in their words.
        public let title: String
        /// What it will take to get it back.
        public let cost: String
        public let bytes: Int64

        /// The path, for the plan to print. Nil for anything that isn't a file.
        public var url: URL? {
            if case .path(let url) = target { return url }
            return nil
        }

        public var exists: Bool {
            switch target {
            case .path(let url):             return FileManager.default.fileExists(atPath: url.path)
            case .storeCredentials(.gog):    return GOGAuth.isSignedIn
            case .storeCredentials:          return false
            }
        }
    }

    /// Everything Cellar owns on this Mac, in the order a person would think about it.
    public static func plan() -> [Item] {
        var items: [Item] = []
        func add(_ url: URL, _ title: String, _ cost: String) {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            items.append(Item(target: .path(url), title: title, cost: cost, bytes: size(of: url)))
        }
        add(Paths.sharedSteam, "Windows Steam and every game installed in it",
            "re-downloaded from Steam — the client is ~1.4 GB, the games are their own size")
        add(Paths.prefixes, "Bottles (Wine prefixes, registries, save-game folders)",
            "rebuilt by setting a game up again")
        add(Paths.runners, "Wine runners", "re-downloaded on the next setup (~1–2 GB)")
        add(DepotTool.root, "DepotDownloader and your Steam sign-in",
            "re-downloaded, and one QR scan to sign in again")
        add(Paths.shared.appendingPathComponent("libraries"), "The cached list of what you own",
            "re-read from the stores when you next refresh")
        add(SteamAccount.recordFile, "Cellar's record of your Steam account", "one QR scan")
        add(Paths.cache, "Downloaded installers and other scratch files", "re-downloaded when needed")
        add(Paths.logs, "Logs", "nothing to restore")
        add(Paths.userProfiles, "Game profiles you added yourself",
            "re-added by hand — Cellar's own profiles ship with the app and come back on their own")
        // The keychain, last, because it is the one thing here that is a credential rather than a
        // download. Steam's token goes with DepotDownloader's directory above; GOG's does not live
        // in a file at all.
        if GOGAuth.isSignedIn {
            items.append(Item(target: .storeCredentials(.gog),
                              title: "Your GOG sign-in (an OAuth token in your login keychain)",
                              cost: "one sign-in", bytes: 0))
        }
        return items
    }

    /// Saves live inside a bottle's `drive_c/users`, so wiping bottles wipes saves that the game
    /// never synced to a cloud. Named explicitly, because "it deletes bottles" does not read as
    /// "it deletes your saves" to anybody who isn't holding the source.
    public static func saveGameWarning(in items: [Item]) -> String? {
        guard items.contains(where: { $0.target == .path(Paths.prefixes) }) else { return nil }
        return "Local save games live inside bottles. Anything a game only saved on this Mac — not to Steam Cloud — goes with them."
    }

    public static func totalBytes(_ items: [Item]) -> Int64 { items.reduce(0) { $0 + $1.bytes } }

    /// Delete everything in `items`. Each is removed independently: one failure (a file held open
    /// by a running game, say) must not leave the rest half-done and unexplained.
    @discardableResult
    public static func perform(_ items: [Item], progress: (String) -> Void = { _ in }) -> [String] {
        var failures: [String] = []
        for item in items where item.exists {
            progress("Removing \(item.title.lowercased())…")
            do {
                switch item.target {
                case .path(let url):
                    try FileManager.default.removeItem(at: url)
                case .storeCredentials(.gog):
                    try GOGAuth.signOut()
                    StoreLibrary.forgetGOG()
                case .storeCredentials(let store):
                    throw CellarError.invalidArgument("No credential store for \(store.displayName).")
                }
            } catch {
                let name = item.url?.lastPathComponent ?? item.title
                failures.append("\(name): \(error.localizedDescription)")
            }
        }
        return failures
    }

    /// A directory's size on disk, for the plan. Walks file sizes only — no contents are read.
    static func size(of url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        guard isDirectory.boolValue else {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            let values = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }

    /// "34.2 GB" — sizes in the units the Finder uses, because that is the number the player will
    /// compare against their free space.
    public static func humanSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
