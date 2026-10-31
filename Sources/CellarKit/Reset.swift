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
            /// A line Cellar wrote into the *native* Steam client's shortcut database. Not a file of
            /// ours, which is exactly why it needs naming: deleting Cellar's folder leaves the entry
            /// behind, pointing at a launcher that no longer exists.
            case steamShortcuts([String])
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
            case .steamShortcuts(let names):  return !names.isEmpty
            case .storeCredentials(.gog):    return GOGAuth.isSignedIn || GOGAuth.cachedUsername != nil
            case .storeCredentials(.steam):  return !Reset.steamTokenStoresOutsideCellar.isEmpty || SteamTokenVault.isSealed
            case .storeCredentials:          return false
            }
        }
    }

    /// Everything Cellar owns on this Mac, in the order a person would think about it.
    ///
    /// "Everything" is the whole promise of this command, so it deliberately reaches **outside**
    /// `~/Library/Application Support/Cellar`. Cellar also writes launcher `.app`s into
    /// `~/Applications` and lines into the native Steam client's shortcut database, and a reset that
    /// left those behind handed the player a Launchpad full of icons that open nothing — which is
    /// precisely what happened before this was fixed. `Uninstall` has always cleaned both for a
    /// single game; this is the same discipline for all of them.
    ///
    /// `includingCellarItself` adds the app and the CLI — a true uninstall rather than a clean
    /// slate. It is off by default because `cellar reset` is normally run to *keep* using Cellar.
    public static func plan(includingCellarItself: Bool = false) -> [Item] {
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
        add(Paths.shared.appendingPathComponent("libraries"),
            "The cached list of what you own, and the Battle.net account you added",
            "re-read from the stores when you next refresh; Battle.net added again in Accounts")
        add(SteamAccount.recordFile, "Cellar's record of your Steam account", "one QR scan")
        add(Paths.cache, "Downloaded installers and other scratch files", "re-downloaded when needed")
        add(Paths.gameApps, "The app each game runs as, so macOS treats it as a game",
            "remade the next time you press Play")
        add(Paths.logs, "Logs", "nothing to restore")
        add(Paths.userProfiles, "Game profiles you added yourself",
            "re-added by hand — Cellar's own profiles ship with the app and come back on their own")
        // Credentials, last, because they are the one thing here that is not a download.
        //
        // Steam's token does *not* reliably go with DepotDownloader's directory above: DepotDownloader
        // 3.4.0 ignores the `HOME` Cellar gives it and writes its store into the shared .NET isolated
        // storage in `~/Library`. A reset that only removed Cellar's folder printed "Clean slate."
        // and left a working Steam refresh token behind — so the stores are named and removed here.
        //
        // Never from a relocated Cellar (`CELLAR_HOME`): those stores and the login keychain are the
        // player's real ones, and a test or a throwaway install must not sign the player out.
        if !isRelocated {
            let strays = steamTokenStoresOutsideCellar
            if !strays.isEmpty || SteamTokenVault.isSealed {
                items.append(Item(target: .storeCredentials(.steam),
                                  title: "Your Steam sign-in token (in your keychain, or DepotDownloader's file)",
                                  cost: "one QR scan", bytes: strays.reduce(0) { $0 + size(of: $1) }))
            }
            if GOGAuth.isSignedIn || GOGAuth.cachedUsername != nil {
                items.append(Item(target: .storeCredentials(.gog),
                                  title: "Your GOG sign-in (an OAuth token in your login keychain)",
                                  cost: "one sign-in", bytes: 0))
            }
        }

        // Outside Application Support. Found by identity, never by name, so nothing the player made
        // themselves is ever in this list.
        for app in AppBundle.generatedApps() {
            items.append(Item(target: .path(app),
                              title: "Launcher app \"\(app.deletingPathExtension().lastPathComponent)\"",
                              cost: "re-created by setting the game up again", bytes: size(of: app)))
        }
        if let config = SteamShortcuts.userdataConfigDir() {
            let names = SteamShortcuts.cellarEntryNames(pointingInto: AppBundle.applicationsDirectory,
                                                        in: config)
            if !names.isEmpty {
                items.append(Item(target: .steamShortcuts(names),
                                  title: "Entries Cellar added to your Steam library (\(names.count))",
                                  cost: "re-added by cellar steam add", bytes: 0))
            }
        }

        if includingCellarItself {
            let apps = cellarApps
            for app in apps { add(app, "Cellar.app (\(app.deletingLastPathComponent().path))", "download it again") }
            // A CLI inside an app being removed goes with it; listing it twice would overstate.
            for cli in cellarCLIs where !apps.contains(where: { cli.path.hasPrefix($0.path + "/") }) {
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: cli.path, isDirectory: &isDirectory)
                add(cli, isDirectory.boolValue ? "The cellar command's profiles and helpers"
                                               : "The cellar command-line tool", "download it again")
            }
            for (url, title) in macOSRecords {
                add(url, title, "nothing to restore — Cellar starts with its defaults")
            }
        }
        return items
    }

    /// The identifier every Cellar.app carries, whatever its file is called.
    static let appIdentifier = "it.clercq.cellar.app"

    /// Where a Cellar.app may be: next to the generated launchers (where `install-app.sh` puts it),
    /// in /Applications (where the DMG puts it), or wherever this process is running from. Each one
    /// is only counted if its Info.plist says it *is* Cellar — never by file name alone.
    ///
    /// A relocated Cellar (`CELLAR_HOME` / `CELLAR_APPLICATIONS_DIR`, which tests and throwaway
    /// installs use) only ever looks inside its own applications folder, so it can never plan to
    /// remove the player's real copy.
    static var cellarApps: [URL] {
        var candidates = [AppBundle.applicationsDirectory.appendingPathComponent("Cellar.app", isDirectory: true)]
        if !isRelocated {
            candidates.append(URL(fileURLWithPath: "/Applications/Cellar.app", isDirectory: true))
            if Bundle.main.bundleURL.pathExtension == "app" { candidates.append(Bundle.main.bundleURL) }
        }
        var seen = Set<String>()
        return candidates.filter { url in
            seen.insert(url.standardizedFileURL.path).inserted && isCellarApp(url)
        }
    }

    /// Whether a bundle is Cellar by what it says it is, not by what it is called.
    static func isCellarApp(_ url: URL) -> Bool {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return false }
        return info["CFBundleIdentifier"] as? String == appIdentifier
    }

    /// The first Cellar.app found, for the plan's "this stays" list.
    static var cellarApp: URL {
        cellarApps.first ?? AppBundle.applicationsDirectory.appendingPathComponent("Cellar.app", isDirectory: true)
    }

    /// The CLI: the running binary, and the copy `install-app.sh` puts in ~/.local with its
    /// profiles beside it. Only files that are really there, and really named `cellar`.
    static var cellarCLIs: [URL] {
        var found: [URL] = []
        if let running = cellarBinary { found.append(running) }
        if !isRelocated {
            let local = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local")
            let bin = local.appendingPathComponent("bin/cellar")
            if FileManager.default.isExecutableFile(atPath: bin.path) {
                found.append(bin)
                found.append(local.appendingPathComponent("share/cellar", isDirectory: true))
            }
        }
        var seen = Set<String>()
        return found.map { $0.resolvingSymlinksInPath().standardizedFileURL }
            .filter { seen.insert($0.path).inserted }
    }

    /// What macOS keeps on Cellar's behalf, outside its own folder: the app's preferences, the
    /// updater's caches, the web view's storage from signing in to GOG, the saved window state.
    /// Left out when relocated — those belong to the player's real installation.
    static var macOSRecords: [(URL, String)] {
        guard !isRelocated else { return [] }
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let id = appIdentifier
        return [
            (library.appendingPathComponent("Preferences/\(id).plist"), "Cellar's settings"),
            (library.appendingPathComponent("Caches/\(id)", isDirectory: true), "Cellar's caches"),
            (library.appendingPathComponent("HTTPStorages/\(id)", isDirectory: true), "Cellar's web storage"),
            (library.appendingPathComponent("WebKit/\(id)", isDirectory: true), "The GOG sign-in page's storage"),
            (library.appendingPathComponent("Saved Application State/\(id).savedState", isDirectory: true),
             "Cellar's saved window positions"),
        ]
    }

    static var isRelocated: Bool {
        let env = ProcessInfo.processInfo.environment
        return !(env["CELLAR_HOME"] ?? "").isEmpty || !(env["CELLAR_APPLICATIONS_DIR"] ?? "").isEmpty
    }

    static var cellarBinary: URL? {
        let path = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            .resolvingSymlinksInPath().standardizedFileURL
        guard path.isFileURL, FileManager.default.isExecutableFile(atPath: path.path),
              path.lastPathComponent == "cellar" else { return nil }
        return path
    }

    /// What `reset` deliberately leaves behind, so the plan can say so rather than implying a
    /// completeness it does not have. Empty once `--everything` has taken them.
    public static func leftBehind(after items: [Item]) -> [URL] {
        let removing = Set(items.compactMap(\.url))
        var rest: [URL] = []
        for app in cellarApps where !removing.contains(app) { rest.append(app) }
        if let cli = cellarBinary, !removing.contains(cli),
           !removing.contains(where: { cli.path.hasPrefix($0.path + "/") }) {
            rest.append(cli)
        }
        return rest
    }

    /// Saves live inside a bottle's `drive_c/users`, so wiping bottles wipes saves that the game
    /// never synced to a cloud. Named explicitly, because "it deletes bottles" does not read as
    /// "it deletes your saves" to anybody who isn't holding the source.
    /// `backedUp` is whether `perform` will copy them out first — it does, unless Cellar itself is
    /// going and the copies would go with it.
    public static func saveGameWarning(in items: [Item], backedUp: Bool = true) -> String? {
        guard items.contains(where: { $0.target == .path(Paths.prefixes) }) else { return nil }
        return backedUp
            ? "Local save games live inside bottles. Cellar backs them up first and keeps the copies (cellar saves list <game>); the bottles themselves go."
            : "Local save games live inside bottles. Anything a game only saved on this Mac — not to Steam Cloud — goes with them."
    }

    public static func totalBytes(_ items: [Item]) -> Int64 { items.reduce(0) { $0 + $1.bytes } }

    /// Delete everything in `items`. Each is removed independently: one failure (a file held open
    /// by a running game, say) must not leave the rest half-done and unexplained.
    @discardableResult
    ///
    /// Removing the bottles backs up every bottle's save games first (`SaveBackups`), and keeps the
    /// bottles if that fails. `backUpSaves: false` is for removing Cellar outright, where the backups
    /// would go with it and the player has already been asked about their saves.
    public static func perform(_ items: [Item], backUpSaves: Bool = true,
                               progress: (String) -> Void = { _ in }) -> [String] {
        var failures: [String] = []
        var savesAtRisk: [String] = []
        if backUpSaves, items.contains(where: { $0.target == .path(Paths.prefixes) && $0.exists }) {
            progress("Backing up save games before the bottles go…")
            savesAtRisk = SaveBackups.backUpAllBottles(reason: .beforeReset, progress: progress)
        }
        // Cellar's Steam token also sits in every bottle's client (`SteamClientSession`). A reset
        // that takes the sign-in away but keeps the bottles would otherwise leave that copy behind,
        // still signing the player in — so it goes first, while the account name is still readable.
        let removingSignIn = items.contains { $0.target == .path(DepotTool.root) }
            || items.contains { $0.target == .storeCredentials(.steam) }
            || items.contains { $0.target == .path(SteamAccount.recordFile) }
        if removingSignIn, let account = SteamAccount.record?.accountName,
           !items.contains(where: { $0.target == .path(Paths.prefixes) }) {
            progress("Taking the Steam sign-in back out of your bottles…")
            SteamBottle.forgetClientSessions(account: account)
        }
        for item in items where item.exists {
            if item.target == .path(Paths.prefixes), !savesAtRisk.isEmpty {
                failures.append("Bottles kept: couldn't back up the save games in \(savesAtRisk.joined(separator: ", ")) first.")
                continue
            }
            progress("Removing \(item.title.lowercased())…")
            do {
                switch item.target {
                case .path(let url):
                    try FileManager.default.removeItem(at: url)
                case .steamShortcuts(let names):
                    guard let config = SteamShortcuts.userdataConfigDir() else { break }
                    for name in names {
                        try SteamShortcuts.remove(appName: name, from: config)
                    }
                case .storeCredentials(.gog):
                    try GOGAuth.signOut()
                    // Every item under Cellar's GOG service, not only today's account name: an item
                    // filed under an older one is still somebody's token.
                    try Keychain.removeAll(store: .gog)
                    StoreLibrary.forgetGOG()
                case .storeCredentials(.steam):
                    for file in steamTokenStoresOutsideCellar { try FileManager.default.removeItem(at: file) }
                    try SteamTokenVault.forget()
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

    /// DepotDownloader's token stores that removing `DepotTool.root` would not reach. Only the
    /// `account.config` files — isolated storage is shared with other .NET programs, and resetting
    /// Cellar is no licence to delete their state.
    static var steamTokenStoresOutsideCellar: [URL] {
        DepotTool.storedSessionFiles.filter { !$0.path.hasPrefix(DepotTool.root.path + "/") }
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
