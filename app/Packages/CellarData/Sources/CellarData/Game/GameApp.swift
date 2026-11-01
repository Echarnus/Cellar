import CellarDomain
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
/// Wine still has to find the rest of itself. Its loader works out where `ntdll.so` is from
/// `argv[0]` (Wine 10.x: the real path of `argv[0]`, then `WINEDLLPATH`; Wine 11+: beside its own
/// executable, then beside `argv[0]` — `loader/main.c`), so the copy is started with `argv[0]`
/// naming the runner's own binary, and finds the runner. Everything after that (ntdll, the
/// server, child processes) resolves from the runner's real path, exactly as before. If a runner
/// re-executes itself into its own loader at startup, the game simply runs as it always did: no
/// Game Mode, nothing broken.
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
    public static func bundleURL(name: String, slug: String) -> URL {
        Paths.gameApps.appendingPathComponent("\(fileName(for: name, slug: slug)).app", isDirectory: true)
    }

    /// Where versions before the bundle took the game's name kept it: `<slug>.app`. The Dock names
    /// a running app after its bundle's file name, so that one showed "fallout-shelter".
    static func legacyBundleURL(slug: String) -> URL {
        Paths.gameApps.appendingPathComponent("\(slug).app", isDirectory: true)
    }

    /// The bundle's file name: the game's own name, exactly as the player reads it, because that is
    /// what the Dock, ⌘-Tab and Activity Monitor show. A `/` cannot be in a file name and a `:` is
    /// shown as `/` by Finder, so both become the look-alike characters macOS uses in their place.
    static func fileName(for name: String, slug: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "\u{2215}")   // ∕ division slash
            .replacingOccurrences(of: ":", with: "\u{A789}")   // ꞉ modifier letter colon
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !cleaned.hasPrefix(".") else { return slug }
        return cleaned
    }

    /// How to start the game from its app: the loader to copy into it, the `argv[0]` to give that
    /// copy so Wine finds the rest of itself, and whether to skip Wine's first-run re-exec.
    public struct Start: Equatable, Sendable {
        /// The copy inside the game's `.app` — what actually runs.
        public let executable: URL
        /// The runner's own loader, passed as `argv[0]`.
        public let argv0: String
        /// Extra environment for the start.
        public let environment: [String: String]
    }

    /// Which of the runner's files the game's process ends up running as — the one to copy — and
    /// whether Wine has to be told not to re-exec. Copying the wrong one is invisible: Wine would
    /// re-exec from the bundle into the runner, and the game would be "wine" again.
    ///
    /// - **Wine 11 layout** (WineForge today): `lib/wine/<arch>-unix/wine` sits beside `ntdll.so`
    ///   and is the loader Wine execs every process into; `bin/wine` is only the first-run wrapper
    ///   that re-execs into it. So the inner loader is copied and started the way Wine starts its
    ///   own child processes — `WINELOADERNOEXEC=1`, no re-exec. It finds `ntdll.so` beside
    ///   `argv[0]` (`loader/main.c`).
    /// - **Wine 10 layout**: `bin/wine` is the loader itself and finds `ntdll.so` at
    ///   `../lib/wine/<arch>-unix/` from the real path of `argv[0]`, or through `WINEDLLPATH`.
    ///   Started as it always is: a runner built with a separate preloader re-execs, and the game
    ///   then runs as before, without the bundle.
    ///
    /// GPTK-style `wine64` + `wine64-preloader` runners are left alone.
    static func loader(for binary: URL) -> (file: URL, noExec: Bool)? {
        let fm = FileManager.default
        let real = binary.resolvingSymlinksInPath()
        guard real.lastPathComponent == "wine" else { return nil }
        let dir = real.deletingLastPathComponent()
        if fm.fileExists(atPath: dir.appendingPathComponent("ntdll.so").path) { return (real, true) }
        for arch in ["x86_64-unix", "aarch64-unix"] {
            let unix = dir.deletingLastPathComponent().appendingPathComponent("lib/wine/\(arch)", isDirectory: true)
            guard fm.fileExists(atPath: unix.appendingPathComponent("ntdll.so").path) else { continue }
            let inner = unix.appendingPathComponent("wine")
            if fm.isExecutableFile(atPath: inner.path) { return (inner.resolvingSymlinksInPath(), true) }
            return (real, false)
        }
        return nil
    }

    /// Whether a launch with this runner can start the game from its game app at all — without
    /// writing anything. What the Steam route asks before choosing to start a game itself.
    public static func isAvailable(runnerBinary: URL) -> Bool {
        ProcessInfo.processInfo.environment[disableVariable] != "1" && loader(for: runnerBinary) != nil
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

    /// Make sure the game's app exists and carries this runner's loader, and return how to start
    /// the game from it. Nil means "start it the usual way": the runner's layout doesn't
    /// allow it, it was switched off, or the bundle couldn't be written. Never a reason not to play.
    public static func prepare(name: String, slug: String, runnerBinary: URL, icon: URL?) -> Start? {
        if ProcessInfo.processInfo.environment[disableVariable] == "1" { return nil }
        guard let loader = loader(for: runnerBinary) else { return nil }
        let fm = FileManager.default
        let app = bundleURL(name: name, slug: slug)
        // A bundle from before it took the game's name is replaced by this one, not kept beside it.
        let legacy = legacyBundleURL(slug: slug)
        if legacy.standardizedFileURL != app.standardizedFileURL { try? fm.removeItem(at: legacy) }
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        let executable = macOS.appendingPathComponent("wine")
        do {
            try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            var changed = false

            // A runner update replaces the loader; the copy must follow it, byte for byte.
            let source = try Data(contentsOf: loader.file)
            if (try? Data(contentsOf: executable)) != source {
                try? fm.removeItem(at: executable)
                try fm.copyItem(at: loader.file, to: executable)
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
            return Start(executable: executable, argv0: loader.file.path,
                         environment: loader.noExec ? ["WINELOADERNOEXEC": "1"] : [:])
        } catch {
            CellarLog.failure(.launch, "Couldn't prepare \(name)'s app bundle; starting it the usual way",
                              error, subject: slug)
            return nil
        }
    }

    /// `prepare` for a plan and the runner about to start it.
    public static func prepare(for plan: GamePlan, runner: WineRunner) -> Start? {
        prepare(name: plan.name, slug: plan.slug, runnerBinary: runner.binary,
                icon: AppBundle.resolveGameICNS(slug: plan.slug, prefix: plan.prefix,
                                                appID: plan.appID, installRoots: plan.installRoots))
    }
}
