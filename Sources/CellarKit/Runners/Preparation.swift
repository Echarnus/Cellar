import CellarDomain
import Foundation

/// Getting the parts every game shares onto the Mac before the player picks one.
///
/// Without this, the first Install press pays for all of it at once: the Wine runner (1–2 GB),
/// DepotDownloader, and — for the Steam games that talk to a running client — the Windows Steam
/// client and its first self-update (another ~1.4 GB). That is a long, unexplained wait in front of
/// the one moment that decides whether Cellar feels like it works. None of it depends on which game
/// comes first, so the app starts it on first launch, in the background, while the player is still
/// reading the welcome tour and signing in. `cellar prepare` is the same thing from a terminal.
///
/// Nothing here is bundled with Cellar. The runner (and the D3DMetal it carries) and the Steam
/// client are fetched from their publishers on the player's own Mac, exactly as a game's setup
/// would fetch them (docs/LEGAL.md) — this only changes *when*.
public enum Preparation {

    /// One shared part, and whether it is already here.
    public enum Part: String, Sendable, CaseIterable {
        case runtime, depotDownloader, steamClient

        /// What the player is waiting for, in their words.
        public var title: String {
            switch self {
            case .runtime:         return "The Windows runtime (Wine)"
            case .depotDownloader: return "The game downloader"
            case .steamClient:     return "The Windows Steam client"
            }
        }

        /// Roughly how much it costs, so a "few gigabytes" claim is never a surprise.
        public var size: String {
            switch self {
            case .runtime:         return "about 1–2 GB"
            case .depotDownloader: return "about 40 MB"
            case .steamClient:     return "about 1.4 GB"
            }
        }
    }

    /// The runner every profile uses unless it names another.
    static var runner: RunnerSpec? { RunnerCatalog.spec(forID: RunnerCatalog.defaultID) }

    /// Whether any game Cellar knows needs a live Windows Steam beside it. If none does, the client
    /// is never part of the plan — downloading 1.4 GB for nothing would be an invented step.
    static var anyGameNeedsSteamClient: Bool {
        ProfileStore.all().contains { ref in
            guard let plan = try? Game.plan(slug: ref.slug) else { return false }
            return plan.store == .steam && plan.needsLiveSession
        }
    }

    /// Whether a part is already on this Mac. File checks only — safe to call from a view.
    public static func isReady(_ part: Part) -> Bool {
        switch part {
        case .runtime:
            return runner.map { RunnerManager.find(id: $0.id) != nil } ?? false
        case .depotDownloader:
            return DepotTool.isInstalled
        case .steamClient:
            return SteamBottle.isSharedInstallPresent
                && SteamClientUpdate.isComplete(inSteamDirectory: SteamBottle.sharedInstall)
        }
    }

    /// The parts still to fetch. `includeSteam` false leaves the client out, for a player who has
    /// said they don't want it ahead of time (and for a test that must not touch Wine).
    public static func missing(includeSteam: Bool = true) -> [Part] {
        var parts: [Part] = [.runtime, .depotDownloader]
        if includeSteam && anyGameNeedsSteamClient { parts.append(.steamClient) }
        return parts.filter { !isReady($0) }
    }

    /// Whether everything is in place. The app asks this on launch; it reads files (and the
    /// profiles, only when Steam is not there yet) and never starts a process.
    public static var isComplete: Bool {
        isReady(.runtime) && isReady(.depotDownloader)
            && (isReady(.steamClient) || !anyGameNeedsSteamClient)
    }

    /// The bottle the Steam client is installed through. The client lands in the shared install
    /// (`SteamBottle.linkIntoBottle`), which outlives it; the bottle itself is scaffolding and is
    /// removed afterwards. Named so it can never collide with a game's bottle.
    static let scaffoldBottle = "cellar-preparation"

    /// Fetch whatever is missing. Each part is independent: a Steam CDN having a bad minute does
    /// not throw away a runner that downloaded fine. Returns the parts that failed, with why.
    ///
    /// Holds `SetupLock` throughout, so a game set up at the same moment waits for this rather than
    /// unpacking the same runner into the same directory alongside it.
    @discardableResult
    public static func run(includeSteam: Bool = true, progress: (String) -> Void = { _ in },
                           phase: (InstallProgress) -> Void = { _ in }) throws -> [(Part, String)] {
        guard SystemEnvironment.isAppleSilicon else {
            throw CellarError.invalidArgument("Cellar requires an Apple Silicon Mac.")
        }
        return try SetupLock.withLock(waiting: progress) { () throws -> [(Part, String)] in
            var failures: [(Part, String)] = []
            let todo = missing(includeSteam: includeSteam)
            if todo.isEmpty { progress("Everything every game shares is already here.") }
            CellarLog.info(.setup, "Preparing ahead of the first game: "
                + (todo.isEmpty ? "nothing missing" : todo.map(\.rawValue).joined(separator: ", ")))

            var install: RunnerInstall?
            for part in todo {
                progress("\(part.title) — \(part.size)…")
                do {
                    switch part {
                    case .runtime:
                        guard let spec = runner else { throw CellarError.invalidArgument("No default runner.") }
                        if spec.architecture.needsRosetta, !SystemEnvironment.rosettaWorks {
                            throw CellarError.invalidArgument(SystemEnvironment.rosettaMissingMessage())
                        }
                        phase(InstallProgress(.runtime))
                        install = try RunnerManager.install(spec, progress: progress)
                    case .depotDownloader:
                        try DepotTool.install(progress: progress)
                    case .steamClient:
                        guard let spec = runner,
                              let runnerInstall = install ?? RunnerManager.find(id: spec.id) else {
                            throw CellarError.invalidArgument("The Windows runtime has to be in place first.")
                        }
                        try installSteamClient(runner: runnerInstall, progress: progress, phase: phase)
                    }
                } catch {
                    CellarLog.warn(.setup, "Preparing \(part.rawValue) failed: \(error.localizedDescription)")
                    failures.append((part, error.localizedDescription))
                }
            }
            return failures
        }
    }

    /// Install and first-update the shared Windows Steam through a scaffold bottle, then take the
    /// scaffold down. Every Steam game's bottle links to the same install later, so what is done
    /// here is never done again.
    static func installSteamClient(runner: RunnerInstall, progress: (String) -> Void,
                                   phase: (InstallProgress) -> Void) throws {
        let prefix = Paths.prefixes.appendingPathComponent(scaffoldBottle, isDirectory: true)
        let wine = WineRunner(install: runner, prefix: prefix)
        // A scaffold left by an interrupted run is started over; nothing of the player's is in it.
        if FileManager.default.fileExists(atPath: prefix.path) {
            wine.killServer()
            try? FileManager.default.removeItem(at: prefix)
        }
        defer {
            wine.killServer()
            // Removing the bottle removes its symlink to the shared install, never the install.
            try? FileManager.default.removeItem(at: prefix)
        }

        phase(InstallProgress(.bottle))
        try PrefixManager.create(name: scaffoldBottle, backend: .d3dmetal, runner: runner.spec.id)
        progress("Preparing a Windows environment to install Steam into…")
        try wine.initializePrefix(checkingHomeFolders: false)
        try wine.setWindowsVersion("win10")

        if !SteamBottle.isSharedInstallPresent { phase(InstallProgress(.client)) }
        try SteamBottle.install(runner: wine, progress: progress)
        try SteamBottle.updateClient(runner: wine, progress: progress) {
            phase(InstallProgress(.clientUpdate, fraction: $0))
        }
        guard SteamClientUpdate.isComplete(inSteamDirectory: SteamBottle.sharedInstall) else {
            throw CellarError.ioFailure("Steam installed but did not finish its first update. "
                + "It will finish when you first set up a Steam game.")
        }
        progress("Steam is ready — shared by every Steam game.")
    }
}
