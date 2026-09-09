import Foundation

/// How much of a game's footprint to remove.
public enum RemovalScope: String, Sendable, CaseIterable {
    /// The game's own files, and the things Cellar made *for that game* — its launcher app, its
    /// extracted icon, its entry in the native Steam library. The bottle, the runner, the store
    /// client and the sign-in all survive, so re-installing is a download and nothing else.
    case game
    /// The game *and* the bottle it lived in: the Wine prefix with its registry, the store client
    /// installed into it, and the launchers Cellar generated for that bottle. The runner is shared
    /// by every bottle and the account is shared by every game, so neither is touched.
    case bottle
}

/// One thing a removal will delete, resolved and measured before anything is touched.
public struct RemovalItem: Sendable, Identifiable {
    public enum Kind: Sendable {
        /// A file or directory on disk.
        case path
        /// An entry inside the native macOS Steam client's `shortcuts.vdf` — not a file of ours to
        /// delete, a line to take back out of somebody else's database.
        case steamShortcut
    }

    /// What this is, in the player's words: "Game files", "Launcher app".
    public let label: String
    public let url: URL
    public let bytes: Int64
    public let kind: Kind
    /// Whether this is the game's own data, as opposed to something Cellar generated around it (a
    /// launcher app, an icon, a log). A plan with none of it is a tidy-up, not an uninstall — and
    /// says so, rather than claiming to have removed a game that was never installed.
    public let isGameData: Bool

    public var id: String { "\(kind)-\(url.path)" }

    /// The path as a person would write it — `~/Library/…`, not `/Users/someone/Library/…`.
    public var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

/// Everything a removal would do, decided before it does any of it.
///
/// Deleting the wrong directory here costs a 90 GB re-download or a sign-in, so removal is a plan
/// first: paths resolved, sizes measured, what survives written down, and anything that makes the
/// removal unsafe raised as a blocker. The CLI prints it and asks; the app shows it in a dialog.
/// Neither of them decides *what* gets deleted — that lives here.
public struct RemovalPlan: Sendable {
    public let slug: String
    public let name: String
    public let store: GameStore
    public let bottleName: String
    public let scope: RemovalScope
    public let items: [RemovalItem]
    /// Sentences naming what deliberately survives. Shown every time: the biggest fear a player has
    /// about an uninstall button is that it takes their account or their other games with it.
    public let kept: [String]
    /// Things worth knowing before saying yes — none of them errors.
    public let warnings: [String]
    /// Why this cannot be carried out. Non-empty means nothing will be deleted; each one ends with
    /// the command or action that resolves it.
    public let blockers: [String]
    /// Whether carrying this out has to close the store's client in the bottle first. Announced up
    /// front, because a client vanishing mid-uninstall otherwise reads as a crash.
    public let closesStoreClient: Bool

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    public var isEmpty: Bool { items.isEmpty }
    /// Whether the game's own files are actually going. False when the game isn't installed and all
    /// that is left behind is something Cellar generated — a tidy-up, and worded as one.
    public var removesGameFiles: Bool { items.contains(where: \.isGameData) }
    public var canProceed: Bool { blockers.isEmpty && !isEmpty }

    /// "12.4 GB" — the number the player is actually deciding about.
    public var totalSizeDescription: String { ByteSize.describe(totalBytes) }
}

/// Removing a game, and everything Cellar put on the machine on its behalf.
///
/// The complication is that a game's footprint is spread across places the player never chose: a
/// Steam library shared by every Steam game, a Wine bottle, a generated `.app` in `~/Applications`,
/// an extracted icon in the cache, a line in the native Steam client's shortcut database. Removing
/// the game means removing exactly those and nothing adjacent — above all not the shared Steam
/// install, which holds the sign-in and every other game.
public enum Uninstall {

    // MARK: - Planning

    public static func plan(for game: GamePlan, scope: RemovalScope) -> RemovalPlan {
        var items: [RemovalItem] = []
        var kept: [String] = []
        var warnings: [String] = []
        var blockers: [String] = []

        items += gameFileItems(game)
        items += generatedItems(for: game, scope: scope)

        if scope == .bottle {
            items += bottleItems(for: game, warnings: &warnings, blockers: &blockers)
        } else if FileManager.default.fileExists(atPath: game.prefix.path) {
            kept.append("The bottle '\(game.bottleName)'"
                + (game.store.descriptor.installsClientInBottle
                   ? " and the \(game.store.displayName) installed in it, so re-installing is just the download."
                   : ", so re-installing is just the download."))
        }

        // The account, and everything that belongs to it rather than to this game.
        kept.append(game.store.descriptor.uninstallKeepsNote)
        // Runners are downloaded once and shared by every bottle, so removing one game never costs
        // another game its runtime.
        kept.append("The Wine runner '\(game.runnerID)', shared by every bottle. Remove runners with: cellar runner remove <id>")

        // Running software holds its files open, and Steam rewrites its manifests as it exits — a
        // removal underneath a live client is how a half-deleted library happens.
        if isGameRunning(game) {
            blockers.append("\(game.name) is running. Quit the game, then try again.")
        }
        // Only worth interrupting the player's client for something that is genuinely holding files
        // open: a stale icon is not worth closing Steam over.
        let touchesFiles = items.contains(where: \.isGameData) || scope == .bottle
        let closesClient = touchesFiles && Game.storeClientRunning(game)
            && game.store.descriptor.requiresClientClosedToUninstall
        if closesClient {
            warnings.append("\(game.store.displayName) is running. Cellar closes it before deleting anything — that is expected, not a crash.")
        }
        // Only when the game's files are actually going: "Steam will show it as not installed" in
        // front of somebody who never installed it is noise dressed up as information.
        if items.contains(where: \.isGameData), let note = game.store.descriptor.uninstallClientNote {
            warnings.append(note)
        }

        return RemovalPlan(
            slug: game.slug, name: game.name, store: game.store, bottleName: game.bottleName,
            scope: scope, items: items, kept: kept, warnings: warnings, blockers: blockers,
            closesStoreClient: closesClient)
    }

    // MARK: - Carrying it out

    /// Delete everything the plan names, in order, reporting each step. Returns the bytes freed.
    ///
    /// Everything that can change while the player reads the plan is asked again here — is the game
    /// running, is the client running, is each path still one Cellar may delete. A plan is a
    /// description of what *would* happen, never a licence to delete what it names: the player can
    /// sit on the confirmation for minutes and start the game in the meantime.
    @discardableResult
    public static func perform(_ plan: RemovalPlan, for game: GamePlan,
                               progress: (String) -> Void = { _ in }) throws -> Int64 {
        if let blocker = plan.blockers.first {
            throw CellarError.invalidArgument(blocker)
        }
        if isGameRunning(game) {
            throw CellarError.invalidArgument("\(game.name) started while you were deciding. Quit it, then try again.")
        }
        guard !plan.isEmpty else { return 0 }

        // Asked now, not read off the plan: a client that came up since the plan was made is holding
        // exactly the files about to be deleted, and the plan would still say there was none.
        let touchesFiles = plan.removesGameFiles || plan.scope == .bottle
        if touchesFiles, game.store.descriptor.requiresClientClosedToUninstall,
           Game.storeClientRunning(game), let wine = Game.wineRunner(game) {
            progress("Closing \(game.store.displayName)…")
            switch game.store {
            case .steam:      SteamBottle.shutdown(runner: wine)
            case .battlenet:  BattleNetBottle.shutdown(runner: wine)
            case .gog, .standalone: break
            }
        }

        // GOG ships an Inno Setup uninstaller. Running it takes the game's registry entries with
        // the files, which deleting the directory alone would leave behind.
        if game.store == .gog, plan.scope != .bottle, let wine = Game.wineRunner(game) {
            runGOGUninstaller(game, runner: wine, progress: progress)
        }

        let fm = FileManager.default
        var freed: Int64 = 0
        for item in plan.items {
            switch item.kind {
            case .steamShortcut:
                progress("Removing '\(item.label)' from your Steam library…")
                do {
                    try SteamShortcuts.remove(appName: plan.name,
                                              launcherPath: generatedLauncherPath(for: plan.name),
                                              from: item.url.deletingLastPathComponent())
                } catch {
                    progress("Couldn't update Steam's shortcuts file: \(error). Remove '\(plan.name)' from Steam by hand.")
                }
            case .path:
                guard isDeletable(item.url) else {
                    throw CellarError.ioFailure(
                        "Refusing to delete \(item.url.path) — it is outside the directories Cellar owns. Nothing was removed.")
                }
                // A symlink is unlinked, never followed: the bottle's `Steam` directory is a link to
                // the shared install that holds the sign-in and every other Steam game.
                if isSymbolicLink(item.url) {
                    progress("Unlinking the bottle's Steam — the shared install it points at, and your sign-in, stay…")
                    try? fm.removeItem(at: item.url)
                    continue
                }
                guard fm.fileExists(atPath: item.url.path) else { continue }
                progress("Removing \(item.label.lowercased()) (\(ByteSize.describe(item.bytes)))…")
                try fm.removeItem(at: item.url)
                freed += item.bytes
            }
        }
        return freed
    }

    // MARK: - What belongs to the game

    /// The game's own files, per store. Only paths that exist, and never a directory that other
    /// games live in — `steamapps/common` holds every Steam game, `drive_c/Games` every GOG one.
    static func gameFileItems(_ game: GamePlan) -> [RemovalItem] {
        var items: [RemovalItem] = []

        if let root = installedRoot(game) {
            items.append(item("Game files", root, gameData: true))
        }

        switch game.store {
        case .steam:
            let steamapps = SteamBottle.steamDirectory(in: game.prefix)
                .resolvingSymlinksInPath().appendingPathComponent("steamapps")
            if let appID = game.appID {
                // The manifest is what Steam reads to decide the game is installed; leaving it
                // behind next to no files is how a client ends up "validating" forever.
                items.append(item("Steam manifest", steamapps.appendingPathComponent("appmanifest_\(appID).acf"), gameData: true))
                items.append(item("Part-downloaded files", steamapps.appendingPathComponent("downloading/\(appID)"), gameData: true))
                items.append(item("Shader cache", steamapps.appendingPathComponent("shadercache/\(appID)")))
                items.append(item("Workshop manifest", steamapps.appendingPathComponent("workshop/appworkshop_\(appID).acf"), gameData: true))
                items.append(item("Workshop content", steamapps.appendingPathComponent("workshop/content/\(appID)"), gameData: true))
            }
        case .gog:
            if let productID = game.gogProductID {
                items.append(item("GOG installer download",
                                  Paths.cache.appendingPathComponent("gog/\(productID)", isDirectory: true)))
            }
        case .battlenet, .standalone:
            break
        }

        // A depot download lands in the bottle even for a store-installed game, so it is checked
        // for whatever the store is — unless it is already the install root above.
        if installedRoot(game)?.standardizedFileURL != game.depotGameDir.standardizedFileURL {
            items.append(item("Downloaded game files", game.depotGameDir, gameData: true))
        }

        return items.filter { $0.bytes > 0 || FileManager.default.fileExists(atPath: $0.url.path) }
    }

    /// Where the game's files actually landed.
    ///
    /// Derived from the exe Cellar can genuinely find, by stripping the profile's relative `exe`
    /// path back off it — exact, and correct whichever of the candidate roots the store's installer
    /// chose. Falls back to Steam's own answer (the `installdir` in its appmanifest) for a Steam
    /// game whose profile names no exe.
    public static func installedRoot(_ game: GamePlan) -> URL? {
        if let exe = game.directLaunchExe, let relative = game.launchExe {
            let depth = relative.split(separator: "/").count
            var root = exe
            for _ in 0..<depth { root = root.deletingLastPathComponent() }
            let candidate = root.resolvingSymlinksInPath()
            return isDeletable(candidate) ? candidate : nil
        }
        if game.store == .steam, let appID = game.appID,
           let dir = SteamBottle.installDirectory(in: game.prefix, appID: appID) {
            let candidate = SteamBottle.steamDirectory(in: game.prefix)
                .resolvingSymlinksInPath()
                .appendingPathComponent("steamapps/common/\(dir)", isDirectory: true)
            guard FileManager.default.fileExists(atPath: candidate.path), isDeletable(candidate) else { return nil }
            return candidate
        }
        return nil
    }

    /// What Cellar generated on the player's behalf for *this game*: the launcher in
    /// `~/Applications`, the icon extracted out of the bottle, the entry in the native Steam client.
    static func generatedItems(for game: GamePlan, scope: RemovalScope) -> [RemovalItem] {
        var items: [RemovalItem] = []

        if let app = generatedApp(named: game.name, identifier: "it.clercq.cellar.\(game.slug)") {
            items.append(item("Launcher app", app))
        }
        items.append(item("Extracted icon", Paths.cache.appendingPathComponent("icons/\(game.slug).icns")))

        // Only the shortcut Cellar wrote — identified by the launcher it points at, not by its name.
        // A player who added the same game to Steam by hand keeps their own entry.
        if let config = SteamShortcuts.userdataConfigDir(),
           SteamShortcuts.contains(appName: game.name, launcherPath: generatedLauncherPath(for: game.name),
                                   in: config) {
            items.append(RemovalItem(label: "Entry in your Steam library",
                                     url: config.appendingPathComponent("shortcuts.vdf"),
                                     bytes: 0, kind: .steamShortcut, isGameData: false))
        }

        if scope == .bottle, game.store.descriptor.installsClientInBottle,
           let app = generatedApp(named: "\(game.store.displayName) (\(game.bottleName))",
                                  identifier: "it.clercq.cellar.\(game.store.rawValue).\(game.bottleName)") {
            items.append(item("\(game.store.displayName) launcher app", app))
        }

        return items.filter { $0.kind == .steamShortcut || FileManager.default.fileExists(atPath: $0.url.path) }
    }

    /// The bottle itself, plus the logs it wrote. Refused outright when another profile shares it —
    /// bottles are per-game by default, but a profile can opt into sharing one, and taking three
    /// games' bottle away to uninstall one of them is not what anybody asked for.
    static func bottleItems(for game: GamePlan, warnings: inout [String],
                            blockers: inout [String]) -> [RemovalItem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: game.prefix.path) else { return [] }

        let sharers = Game.slugs(sharingBottle: game.bottleName).filter { $0 != game.slug }
        if !sharers.isEmpty {
            blockers.append(
                "The bottle '\(game.bottleName)' is shared with \(sharers.joined(separator: ", ")). "
                + "Remove \(game.name)'s files on their own instead: cellar uninstall \(game.slug)")
            return []
        }

        var items: [RemovalItem] = []

        // The bottle's `Steam` is a symlink to the shared install in all but the oldest bottles.
        // Unlink it explicitly rather than trusting a recursive delete to stop at the link.
        let steamPath = SteamBottle.steamDirectory(in: game.prefix)
        if isSymbolicLink(steamPath) {
            items.append(RemovalItem(label: "Link to shared Steam", url: steamPath,
                                     bytes: 0, kind: .path, isGameData: false))
        } else if SteamBottle.hasOwnSteamInstallForDiagnostics(in: game.prefix) {
            warnings.append(
                "This bottle has a Steam install of its own (from before Cellar shared one). It goes with the bottle; the shared install and your sign-in do not.")
        }

        items.append(item("Bottle", game.prefix))
        for log in ["game-\(game.slug).log", "steam-\(game.bottleName).log",
                    "battlenet-\(game.bottleName).log"] {
            items.append(item("Log", Paths.logs.appendingPathComponent(log)))
        }
        return items.filter { $0.bytes > 0 || fm.fileExists(atPath: $0.url.path) }
    }

    // MARK: - Safety

    /// The directories Cellar owns. Anything outside them is never deleted, whatever a profile says.
    static var deletableRoots: [URL] {
        [Paths.appSupport, AppBundle.applicationsDirectory]
    }

    /// Directories that hold *other games' or other accounts'* data. Each is a legitimate parent of
    /// something being removed, and never a removal target itself.
    static var protectedRoots: [URL] {
        var roots = [Paths.appSupport, Paths.shared, Paths.sharedSteam, Paths.prefixes, Paths.runners,
                     Paths.cache, Paths.logs, Paths.userProfiles, AppBundle.applicationsDirectory,
                     Paths.cache.appendingPathComponent("icons"),
                     Paths.cache.appendingPathComponent("gog")]
        let steamapps = Paths.sharedSteam.appendingPathComponent("steamapps")
        roots += [steamapps, steamapps.appendingPathComponent("common"),
                  steamapps.appendingPathComponent("downloading"),
                  steamapps.appendingPathComponent("shadercache"),
                  steamapps.appendingPathComponent("workshop"),
                  steamapps.appendingPathComponent("workshop/content")]
        return roots
    }

    /// Whether Cellar may delete this path: inside a directory it owns, and not one of the shared
    /// parents. The last line of defence — checked when the plan is built *and* again before the
    /// delete, because a plan the player is looking at is already out of date.
    public static func isDeletable(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard path.count > 1, !path.hasSuffix("/") else { return false }
        if protectedRoots.contains(where: { $0.standardizedFileURL.path == path }) { return false }
        // A bottle's own drive_c roots hold everything in the bottle; only the bottle itself, or
        // something below those, may go.
        for suffix in ["/drive_c", "/drive_c/Games", "/drive_c/Program Files",
                       "/drive_c/Program Files (x86)", "/drive_c/users", "/drive_c/ProgramData"] {
            if path.hasSuffix(suffix) { return false }
        }
        return deletableRoots.contains { root in
            path.hasPrefix(root.standardizedFileURL.path + "/")
        }
    }

    /// Whether the game itself is running — asked two ways, because one of them is often unavailable.
    ///
    /// The profile's `exe` / `install_dir` give process needles, but plenty of Steam profiles carry
    /// neither (Steam knows the install directory, so they never had to). For those, Steam's own
    /// appmanifest names it, and `SteamBottle.isGameRunning` matches on that. Missing this is how a
    /// player's live game gets its files deleted out from under it.
    static func isGameRunning(_ game: GamePlan) -> Bool {
        if !game.gameProcessNeedles.isEmpty, ProcessWatch.isRunningAny(game.gameProcessNeedles) {
            return true
        }
        if game.store == .steam, let appID = game.appID,
           SteamBottle.isGameRunning(in: game.prefix, appID: appID) {
            return true
        }
        return false
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        let type = try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
        return type == .typeSymbolicLink
    }

    /// The inner launcher of the `.app` Cellar generates for a game — the exact path it writes into
    /// a Steam shortcut. Computed rather than read, so the shortcut is still identifiable as ours
    /// after the bundle itself is gone.
    static func generatedLauncherPath(for name: String) -> String {
        AppBundle.applicationsDirectory
            .appendingPathComponent("\(name).app/Contents/MacOS/launcher").path
    }

    /// A `.app` in `~/Applications` **that Cellar generated** — matched on the bundle identifier it
    /// writes, so a game's own app of the same name is never mistaken for ours and deleted.
    static func generatedApp(named name: String, identifier: String) -> URL? {
        let app = AppBundle.applicationsDirectory.appendingPathComponent("\(name).app", isDirectory: true)
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == identifier else { return nil }
        return app
    }

    // MARK: - Helpers

    static func item(_ label: String, _ url: URL, gameData: Bool = false) -> RemovalItem {
        RemovalItem(label: label, url: url, bytes: ByteSize.of(url), kind: .path, isGameData: gameData)
    }

    /// Run GOG's own uninstaller inside the bottle so registry entries go with the files. Best
    /// effort: the directory is deleted afterwards regardless, so a missing or wedged uninstaller
    /// costs nothing but the extra seconds.
    static func runGOGUninstaller(_ game: GamePlan, runner: WineRunner, progress: (String) -> Void) {
        guard let root = installedRoot(game) else { return }
        let uninstallers = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("unins") && $0.pathExtension.lowercased() == "exe" } ?? []
        guard let uninstaller = uninstallers.sorted(by: { $0.path < $1.path }).first else { return }
        progress("Running GOG's own uninstaller (silently — nothing to watch)…")
        runner.runExecutable(uninstaller.path, args: ["/VERYSILENT", "/NORESTART"], inheritIO: false)
    }
}

/// Sizes on disk, and how to say them to a person.
public enum ByteSize {
    /// Bytes used by a file or, recursively, a directory. Symlinks are counted as themselves and
    /// never followed — the bottle's Steam link points at every other Steam game.
    public static func of(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if Uninstall.isSymbolicLink(url) { return 0 }
        if !isDirectory.boolValue {
            let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
            return size?.int64Value ?? 0
        }
        // Hidden files are counted: a Wine prefix and a Steam library are full of them, and a total
        // that quietly omits them would understate what the player is about to free.
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
                                             options: []) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// "12.4 GB". Human units, because nobody decides anything from 13 314 398 208.
    public static func describe(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        // Without this an empty directory reads "Zero KB", which looks like a bug in the tally.
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}
