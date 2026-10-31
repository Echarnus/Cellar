import CellarDomain
import Foundation

/// Keeping a game Cellar downloaded itself on the build Steam is serving.
///
/// A copy Steam installed is Steam's to update — it does that on its own every time it starts. A
/// copy Cellar fetched with DepotDownloader is invisible to Steam (there is no appmanifest for it),
/// so nobody would ever update it: the game would sit on the build it was downloaded at until a
/// patch made it refuse to go online. This is the part that notices and catches it up.
///
/// **Steam is the source of truth, both sides.** What is installed is what DepotDownloader recorded
/// in `.DepotDownloader/depot.config` when the download finished; what is current is what Steam
/// hands the same account for the same app today (`-manifest-only`, which moves no game files).
/// They are compared depot by depot, by manifest id — no version strings, no guessing from dates.
public enum GameUpdates {
    /// The answer, as a domain value every layer can name.
    public typealias State = UpdateState

    /// Whether Cellar is the one keeping this copy current: a Steam app it downloaded itself, and
    /// not one Steam's own library also has (Steam updates those, and Play goes through Steam).
    public static func managesUpdates(_ plan: GamePlan) -> Bool {
        guard let appID = plan.appID, DepotManifests.installed(in: plan.depotGameDir) != nil else { return false }
        return !SteamBottle.isGameInstalled(in: plan.prefix, appID: appID)
    }

    /// The last answer, re-read against what is on disk now — so an update that has just finished
    /// reads as up to date without asking Steam again. No network: the library calls this on every
    /// refresh. Nil when Cellar does not manage this copy's updates.
    public static func cachedState(_ plan: GamePlan) -> State? {
        guard managesUpdates(plan), let installed = DepotManifests.installed(in: plan.depotGameDir) else { return nil }
        guard let record = UpdateRecord.load(slug: plan.slug) else { return .unknown("not checked yet") }
        return record.state(against: installed)
    }

    /// Ask Steam which build is current and compare it with the copy on disk. Remembers the answer
    /// for `cachedState`. A few seconds and a few megabytes of manifest; no game files move.
    @discardableResult
    public static func check(_ plan: GamePlan, timeout: TimeInterval = 90) -> State {
        guard let appID = plan.appID,
              let installed = DepotManifests.installed(in: plan.depotGameDir) else {
            return .unknown("Cellar didn't download this copy, so it has nothing to compare")
        }
        guard let credentials = SteamAccount.credentials else {
            return .unknown("not signed in to Steam")
        }
        switch DepotTool.latestManifests(appID: appID, credentials: credentials, timeout: timeout) {
        case .unknown(let why):
            CellarLog.info(.install, "Couldn't check \(plan.name) for updates: \(why)", subject: plan.slug)
            return .unknown(why)
        case .manifests(let latest):
            let record = UpdateRecord(checked: Date(), latest: latest)
            record.save(slug: plan.slug)
            let state = record.state(against: installed)
            let verdict: String
            if case .available = state { verdict = "a newer build is out" } else { verdict = "up to date" }
            CellarLog.info(.install, "Update check for \(plan.name): \(verdict)", subject: plan.slug)
            return state
        }
    }

    /// How long an answer stands before the app asks Steam again — and how long "Up to date" may be
    /// said without its age beside it.
    public static let recheckInterval: TimeInterval = 6 * 60 * 60

    /// Whether `cachedState` is recent enough that asking again would only cost the player time.
    public static func isFresh(_ state: State?, within interval: TimeInterval, now: Date = Date()) -> Bool {
        switch state {
        case .upToDate(let checked), .available(let checked): return now.timeIntervalSince(checked) < interval
        case .unknown, nil: return false
        }
    }

    /// Why an update did not finish — and, the part that matters, whether the files were touched.
    public enum UpdateFailure: Error, LocalizedError, Equatable {
        /// Nothing on disk changed: the build there is exactly as intact as before.
        case notStarted(String)
        /// Files were being replaced when it stopped. The game is in no known state until it resumes.
        case partial(String)
        /// Another download is already writing into this game's folder.
        case alreadyDownloading

        public var errorDescription: String? {
            switch self {
            case .notStarted(let why), .partial(let why): return why
            case .alreadyDownloading: return "another download is already writing into this game's folder"
            }
        }
    }

    /// Bring the copy on disk up to Steam's current build.
    ///
    /// DepotDownloader is pointed at the same directory it downloaded into: it diffs the manifest it
    /// recorded there against the new one and fetches only the chunks that changed, so a patch costs
    /// a patch, not the whole game. It records a depot's new manifest only once that depot is
    /// through, so an interrupted update is resumed by the next run rather than counted as done —
    /// and `depot.config` is read back afterwards, so "updated" never rests on an exit code alone.
    public static func apply(_ plan: GamePlan, progress: (String) -> Void = { _ in },
                             phase: (InstallProgress) -> Void = { _ in }) throws {
        guard let appID = plan.appID else {
            throw UpdateFailure.notStarted("profile '\(plan.slug)' has no steam_appid")
        }
        if let missing = GameStorage.missingDrive(plan) {
            throw UpdateFailure.notStarted("the drive “\(missing)” with the game on it isn't connected")
        }
        guard !DepotTool.isDownloading(into: plan.depotGameDir) else { throw UpdateFailure.alreadyDownloading }
        guard let credentials = SteamAccount.credentials else {
            throw UpdateFailure.notStarted("not signed in to Steam — cellar steam login")
        }
        CellarLog.info(.install, "Updating \(plan.name) (AppID \(appID)).", subject: plan.slug)
        SaveBackups.backUpQuietly(bottle: plan.prefix, reason: .beforeGameUpdate)
        phase(InstallProgress(.updating))
        // DepotDownloader prints a percentage per file it writes, so the first one is the moment the
        // copy on disk stops being the old build.
        var touched = false
        do {
            try withoutActuallyEscaping(progress) { report in
                try withoutActuallyEscaping(phase) { phase in
                    try DepotTool.fetch(appID: appID, into: plan.depotGameDir, credentials: credentials) { line in
                        if let fraction = DepotProgress.fraction(in: line) {
                            touched = true
                            phase(InstallProgress(.updating, fraction: fraction))
                        }
                        report(line)
                    }
                }
            }
        } catch {
            let why = CellarLog.describe(error)
            throw touched ? UpdateFailure.partial(why) : UpdateFailure.notStarted(why)
        }
        if let installed = DepotManifests.installed(in: plan.depotGameDir),
           let record = UpdateRecord.load(slug: plan.slug),
           case .available = record.state(against: installed) {
            throw UpdateFailure.partial("Steam's download ended before every part of the game was current")
        }
        CellarLog.info(.install, "\(plan.name) is up to date.", subject: plan.slug)
    }
}
