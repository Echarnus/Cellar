import Foundation

/// The game's own `.app`, which the game's Wine process runs from — so macOS sees a game.
///
/// macOS turns Game Mode on (CPU and GPU priority, lower Bluetooth latency) for the frontmost
/// full-screen app whose bundle says `LSApplicationCategoryType = public.app-category.games`. Wine
/// is a bare binary with no bundle, so a game run through it is never a game to macOS — whatever
/// category the player's launcher in `~/Applications` declares, because that launcher is a shell
/// script that hands off to `cellar`, and the process on screen is `wine`.
///
/// So Cellar keeps a small bundle per game under `Paths.gameApps` whose executable is a *copy* of
/// the runner's Wine loader, and starts the game's process from it. macOS identifies an app by the
/// bundle its executable sits in, so that process is "Planet Coaster 2", category games: Game Mode,
/// and the game's name and icon everywhere macOS shows a running app.
///
/// Wine still has to find the rest of itself. Its loader looks for `ntdll.so` beside its own
/// executable first and beside `argv[0]` second (`loader/main.c`), so the copy is started with
/// `argv[0]` naming the runner's own binary — the copy finds nothing beside itself, then finds the
/// runner. Everything after that (ntdll, the server, child processes) resolves from the runner's
/// real path, exactly as before. If a runner re-executes itself into its own loader at startup, the
/// game simply runs as it always did: no Game Mode, nothing broken.
///
/// Only the game's own process can be started this way. A game Steam or Battle.net starts is a
/// child of the client, created by Wine from the runner's loader, so it keeps the bundle-less
/// identity; the profiles Cellar launches itself (direct, and Steam games downloaded by Cellar,
/// which run beside the client) are the ones that get it.
public enum GameApp {
    /// The variable that turns this off for one launch — for telling whether a problem is this.
    static let disableVariable = "CELLAR_NO_GAME_APP"

    /// Where the game apps live. Not `~/Applications`: these are runtime plumbing, not something
    /// to open from Finder — double-clicking one would run Wine with no program.
    public static func bundleURL(slug: String) -> URL {
        Paths.gameApps.appendingPathComponent("\(slug).app", isDirectory: true)
    }

    /// The loader to copy, when this runner's layout supports starting it from elsewhere: the real
    /// file behind the runner's `wine`, with `ntdll.so` beside it (Wine 7.x+ layout). GPTK-style
    /// `wine64` + `wine64-preloader` runners re-exec by name and are left alone.
    static func loader(for binary: URL) -> URL? {
        let real = binary.resolvingSymlinksInPath()
        guard real.lastPathComponent == "wine",
              FileManager.default.fileExists(atPath: real.deletingLastPathComponent()
                  .appendingPathComponent("ntdll.so").path) else { return nil }
        return real
    }

    /// The Info.plist of a game app. Mirrors what Wine embeds in its own loader (`LSUIElement`,
    /// `NSPrincipalClass`) so the Mac driver behaves exactly as it does unbundled — it starts as a
    /// background app and turns itself into a regular one when the game shows a window — and adds
    /// what makes it the game: its name, its icon, the games category and Game Mode support.
    static func infoPlist(name: String, slug: String, hasIcon: Bool) -> [String: Any] {
        var info: [String: Any] = [
            "CFBundleExecutable": "wine",
            "CFBundleIdentifier": "it.clercq.cellar.game.\(slug)",
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "CFBundleAllowMixedLocalizations": true,
            "NSPrincipalClass": "WineApplication",
            "LSUIElement": "1",
            "LSApplicationCategoryType": "public.app-category.games",
            "LSSupportsGameMode": true,
            "NSHighResolutionCapable": true,
            "LSMinimumSystemVersion": "27.0",
        ]
        if hasIcon { info["CFBundleIconFile"] = "app" }
        return info
    }

    /// Make sure the game's app exists and carries this runner's loader, and return the executable
    /// to start the game with. Nil means "start it the usual way": the runner's layout doesn't
    /// allow it, it was switched off, or the bundle couldn't be written. Never a reason not to play.
    public static func prepare(name: String, slug: String, runnerBinary: URL, icon: URL?) -> URL? {
        if ProcessInfo.processInfo.environment[disableVariable] == "1" { return nil }
        guard let loader = loader(for: runnerBinary) else { return nil }
        let fm = FileManager.default
        let app = bundleURL(slug: slug)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        let executable = macOS.appendingPathComponent("wine")
        do {
            try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            var changed = false

            // A runner update replaces the loader; the copy must follow it, byte for byte.
            let source = try Data(contentsOf: loader)
            if (try? Data(contentsOf: executable)) != source {
                try? fm.removeItem(at: executable)
                try fm.copyItem(at: loader, to: executable)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
                changed = true
            }

            let iconFile = resources.appendingPathComponent("app.icns")
            if let icon, fm.fileExists(atPath: icon.path),
               (try? Data(contentsOf: iconFile)) != (try? Data(contentsOf: icon)) {
                try? fm.removeItem(at: iconFile)
                try fm.copyItem(at: icon, to: iconFile)
                changed = true
            }

            let plist = try PropertyListSerialization.data(
                fromPropertyList: infoPlist(name: name, slug: slug, hasIcon: fm.fileExists(atPath: iconFile.path)),
                format: .xml, options: 0)
            let plistURL = contents.appendingPathComponent("Info.plist")
            if (try? Data(contentsOf: plistURL)) != plist {
                try plist.write(to: plistURL, options: .atomic)
                changed = true
            }

            if changed {
                Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
                let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
                if fm.fileExists(atPath: lsregister) { Shell.run(lsregister, ["-f", app.path]) }
            }
            return executable
        } catch {
            CellarLog.failure(.launch, "Couldn't prepare \(name)'s app bundle; starting it the usual way",
                              error, subject: slug)
            return nil
        }
    }

    /// `prepare` for a plan and the runner about to start it.
    public static func prepare(for plan: GamePlan, runner: WineRunner) -> URL? {
        prepare(name: plan.name, slug: plan.slug, runnerBinary: runner.binary,
                icon: AppBundle.resolveGameICNS(slug: plan.slug, prefix: plan.prefix,
                                                appID: plan.appID, installRoots: plan.installRoots))
    }
}
