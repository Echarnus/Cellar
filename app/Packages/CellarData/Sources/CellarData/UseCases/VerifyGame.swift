import CellarDomain
import Foundation

/// `cellar verify`: start a game the way Play does, watch it, judge it, close it, and write down
/// what was found (#203).
///
/// Nobody watches it. Every verdict comes from something Cellar can read while the game runs:
/// the store's own logs, the process table, the connections the game's process holds open, the
/// Wine log. The baseline is the same for every game and is never opt-in, because these are the
/// failures that kept reaching Kenneth after something was called done:
///
/// | ID | Asks |
/// |---|---|
/// | `signed-in` | the store signed in by itself, as the player's account, with no sign-in window |
/// | `steam-online` | Steam logged on and stayed online, not in offline mode |
/// | `launch` | Play started the game |
/// | `stays-up` | the game stayed up for the whole run, with no crash reporter and no Wine crash |
/// | `game-online` | the game's own process reached its servers, with no TLS errors on the way |
/// | `dlc` | (Steam) Steam records the game fully installed with every depot, so its DLC is seen |
/// | `dock` | only the game is in the Dock, under its own name; never Wine or the store client |
/// | `settings-match` | the bottle overrides nothing in the profile, and the game runs in the Mac's language |
/// | `clean-exit` | after quitting, nothing of the bottle's Wine is left running |
/// | `real-install-untouched` | the Windows runtime is byte for byte what it was before |
///
/// The IDs are shared with the pre-delivery checklist (`docs/DELIVERY-CHECKLIST.md`).
///
/// Verify runs the real install, through the real Play path, because that is what a player gets.
/// It only ever *reads* the install, apart from what Play itself does; the fingerprint check is
/// there to prove that.
public struct VerifyGame {
    public let plan: GamePlan
    public let adapter: any StoreAdapter
    /// Cold launches in a row. Every one has to pass.
    public var runs: Int
    /// How long each launch has to stay up.
    public var surviveSeconds: Int
    /// How often the process table and the game's connections are read.
    public var sampleSeconds: TimeInterval
    /// Where reports are written: one folder per run of `cellar verify`.
    public var reportsRoot: URL
    /// Bring a Cellar-downloaded game up to date first, as Play does.
    public var checkUpdates = true
    /// Keep a picture of the screen from each launch (needs Screen Recording permission).
    public var screenshots = true
    /// What is in the Dock right now. Replaced in tests, which have no Dock to read.
    public var dockApps: () -> [DockApps.App] = DockApps.current
    /// Whether someone asked verify to stop (Ctrl-C). Checked between runs and every second of a
    /// watch; the run under way is then closed down and the report written with what was done (#249).
    public var isInterrupted: () -> Bool = { false }

    public init(_ plan: GamePlan, runs: Int = 1, surviveSeconds: Int = 300, sampleSeconds: TimeInterval = 10,
                reportsRoot: URL = Paths.appSupport.appendingPathComponent("verify", isDirectory: true),
                adapter: (any StoreAdapter)? = nil) {
        self.plan = plan
        self.runs = max(1, runs)
        self.surviveSeconds = max(0, surviveSeconds)
        self.sampleSeconds = max(1, sampleSeconds)
        self.reportsRoot = reportsRoot
        self.adapter = adapter ?? plan.store.adapter
    }

    /// Verify the game and write the report. Never throws: anything that goes wrong is a check
    /// that failed or could not be done, so the report always says what happened.
    public func run(_ say: (String) -> Void = { _ in }) -> (report: VerificationReport, folder: URL) {
        let started = Date()
        let folder = reportsRoot
            .appendingPathComponent(plan.slug, isDirectory: true)
            .appendingPathComponent(Self.folderName(started), isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let before = CellarSandbox.Fingerprint.of(runnersAt: Paths.runners)
        var checks: [VerificationCheck] = []
        var attachments: [String] = []

        if let busy = alreadyRunning() {
            checks.append(VerificationCheck(
                id: "launch", title: "Play starts the game", verdict: .couldNotCheck,
                detail: "\(plan.name) is already running, and verify won't close a game someone may be playing.",
                evidence: busy))
        } else {
            if let wine = Game.wineRunner(plan), adapter.isClientRunning {
                say("Closing \(plan.store.descriptor.displayName) in the bottle first, so this run starts cold…")
                adapter.shutDownClient(plan, wine: wine)
            }
            // A report from the start, so even a verify that is killed outright leaves one.
            write(makeReport(checks: [Self.judgeInterrupted(stoppedIn: nil, completed: 0, runs: runs, stillRunning: true)],
                             attachments: [], started: started), to: folder)
            for number in 1...runs {
                if isInterrupted() {
                    checks.append(Self.judgeInterrupted(stoppedIn: nil, completed: number - 1, runs: runs))
                    break
                }
                say("Run \(number) of \(runs): starting \(plan.name)…")
                let (found, screenshot) = verifyOneLaunch(number: number, folder: folder, say: say)
                checks += runs == 1 ? found : found.map { $0.inRun(number) }
                if let screenshot { attachments.append(screenshot) }
                if isInterrupted() {
                    checks.append(Self.judgeInterrupted(stoppedIn: number, completed: number - 1, runs: runs))
                    break
                }
                if number < runs {
                    // What is done so far, in case verify never gets to the end (killed, the Mac
                    // asleep): the evidence of a finished run is never lost.
                    var sofar = checks
                    sofar.append(Self.judgeInterrupted(stoppedIn: nil, completed: number, runs: runs, stillRunning: true))
                    write(makeReport(checks: sofar, attachments: attachments, started: started), to: folder)
                }
            }
        }

        let after = CellarSandbox.Fingerprint.of(runnersAt: Paths.runners)
        checks.append(Self.judgeRuntime(before: before, after: after))

        let report = makeReport(checks: checks, attachments: attachments, started: started)
        write(report, to: folder)
        CellarLog.info(.launch, "Verified \(plan.name): \(report.verdict.label). \(report.summary)", subject: plan.slug)
        return (report, folder)
    }

    private func makeReport(checks: [VerificationCheck], attachments: [String], started: Date) -> VerificationReport {
        VerificationReport(slug: plan.slug, name: plan.name, store: plan.store.rawValue, startedAt: started,
                           finishedAt: Date(), environment: environment(), checks: checks, attachments: attachments)
    }

    static let interruptedTitle = "Every run asked for was done"

    /// The `interrupted` check: never a pass, because runs that weren't done prove nothing.
    /// `stoppedIn` is the run that was cut short, nil when verify stopped between runs.
    static func judgeInterrupted(stoppedIn: Int?, completed: Int, runs: Int, stillRunning: Bool = false) -> VerificationCheck {
        let done = "\(completed) of \(runs) run\(runs == 1 ? "" : "s") finished"
        let detail: String
        if stillRunning {
            detail = "Written while verify was still running: \(done). If this is the last report in the folder, verify never got to the end."
        } else if let stoppedIn {
            detail = "Verify was stopped during run \(stoppedIn), which was closed down without being watched to the end; \(done)."
        } else {
            detail = "Verify was stopped before run \(completed + 1) started; \(done)."
        }
        return VerificationCheck(id: "interrupted", title: interruptedTitle, verdict: .couldNotCheck, detail: detail)
    }

    // MARK: - One launch

    private func verifyOneLaunch(number: Int, folder: URL,
                                 say: (String) -> Void) -> ([VerificationCheck], String?) {
        var plan = plan
        plan.env["WINEDEBUG"] = CrashSigns.wineDebug(adding: plan.env["WINEDEBUG"])
        let logs = logFiles()
        let logMarks = logs.map(VerificationLog.mark)
        let storeMark = adapter.verificationMark(plan)

        var steps: [String] = []
        let launch: VerificationCheck
        do {
            let route = try LaunchGame(plan, checkUpdates: checkUpdates, adapter: adapter).run { event in
                if let text = event.sentence {
                    steps.append(text)
                    say("  " + text)
                }
            }
            launch = VerificationCheck(id: "launch", title: "Play starts the game", verdict: .pass,
                                       detail: "Play started \(plan.name) (\(route.logDescription)).")
        } catch {
            launch = VerificationCheck(id: "launch", title: "Play starts the game", verdict: .fail,
                                       detail: "Play didn't start \(plan.name): \(CellarLog.describe(error))",
                                       evidence: steps.suffix(15).map { $0 })
        }

        // Watch it for as long as it has to stay up.
        var watch = Watch()
        if launch.verdict == .pass, isInterrupted() {
            watch.interrupted = true
        } else if launch.verdict == .pass {
            say("  Watching \(plan.name) for \(surviveSeconds / 60 > 0 ? "\(surviveSeconds / 60) min" : "\(surviveSeconds) s")…")
            watch = observe(plan, say: say)
        }
        let screenshot = launch.verdict == .pass && screenshots ? takeScreenshot(run: number, folder: folder) : nil

        let wineLog = zip(logs, logMarks).map { VerificationLog.text(of: $0, since: $1) }.joined(separator: "\n")
        var checks = adapter.verificationChecks(plan, since: storeMark, launchSteps: steps)
        checks.append(launch)
        if launch.verdict == .pass {
            checks.append(Self.judgeStaysUp(watch, wineLog: wineLog, surviveSeconds: surviveSeconds, name: plan.name))
            checks.append(Self.cutShort(Self.judgeOnline(watch, wineLog: wineLog, plan: plan), watch,
                                        failedOnEvidence: !CrashSigns.tlsErrors(inWineLog: wineLog).isEmpty))
            checks.append(Self.cutShort(Self.judgeDock(watch, name: plan.name), watch,
                                        failedOnEvidence: !watch.dockIntruders.isEmpty))
        } else {
            for (id, title) in [("stays-up", Self.staysUpTitle), ("game-online", Self.onlineTitle), ("dock", Self.dockTitle)] {
                checks.append(VerificationCheck(id: id, title: title, verdict: .couldNotCheck,
                                                detail: "The game never started."))
            }
        }

        checks.append(Self.judgeSettings(plan.performance.entries, language: plan.language))

        say("  Closing \(plan.name) and \(plan.store.descriptor.displayName)…")
        checks.append(closeEverything(plan))
        return (checks, screenshot)
    }

    /// What was seen while the game ran.
    struct Watch {
        var watchedSeconds = 0
        var gameSeenRunning = false
        var exitedAfter: Int?
        var crashReporters: [String] = []
        var endpoints = Set<GameConnections.Endpoint>()
        var hostAddresses: [String: Set<String>] = [:]
        /// Times the Dock was read while the game ran, and whether it ever held the game's icon.
        var dockSamples = 0
        var gameInDock = false
        /// Dock icons that shouldn't have been there: "name (path)".
        var dockIntruders: [String] = []
        /// Verify was stopped before the watch was over.
        var interrupted = false
    }

    /// A failure that only means "not seen yet" is no failure when the watch was cut short: it
    /// becomes could-not-check. One found on real evidence (a TLS error, Wine in the Dock) stands.
    static func cutShort(_ check: VerificationCheck, _ watch: Watch, failedOnEvidence: Bool) -> VerificationCheck {
        guard watch.interrupted, check.verdict == .fail, !failedOnEvidence else { return check }
        return VerificationCheck(id: check.id, title: check.title, verdict: .couldNotCheck,
                                 detail: "Verify was stopped after \(watch.watchedSeconds) s, before this could be seen. " + check.detail,
                                 evidence: check.evidence)
    }

    private func observe(_ plan: GamePlan, say: (String) -> Void) -> Watch {
        var watch = Watch()
        let started = Date()
        let hosts = plan.onlineHosts.map(GameConnections.hostName)
        let gameBundle = GameApp.bundleURL(name: plan.name, slug: plan.slug).path
        let runnerRoot = RunnerManager.find(id: plan.runnerID).map { RunnerProcesses.canonicalPath($0.root) }
        while true {
            let elapsed = Int(Date().timeIntervalSince(started))
            watch.watchedSeconds = elapsed
            let table = Self.processTable()
            let reporters = CrashSigns.crashReporters(inProcessList: table, extra: plan.crashProcesses)
            if !reporters.isEmpty {
                watch.crashReporters = reporters
                say("  A crash reporter appeared after \(elapsed) s.")
                break
            }
            let pids = Self.gamePids(inProcessList: table, needles: plan.gameProcessNeedles)
            if pids.isEmpty {
                // Give a client route a moment to hand over from the launcher to the game itself.
                if watch.gameSeenRunning || elapsed > 90 {
                    watch.exitedAfter = elapsed
                    say("  \(plan.name) is no longer running after \(elapsed) s.")
                    break
                }
            } else {
                watch.gameSeenRunning = true
                watch.endpoints.formUnion(GameConnections.established(pids: pids))
                let dock = dockApps()
                if !dock.isEmpty {
                    watch.dockSamples += 1
                    if DockApps.game(in: dock, gameBundle: gameBundle, name: plan.name) != nil { watch.gameInDock = true }
                    for app in DockApps.intruders(in: dock, runnerRoot: runnerRoot, gameBundle: gameBundle) {
                        let seen = "\(app.name) (\(app.bundlePath ?? app.executablePath ?? "no path"))"
                        if !watch.dockIntruders.contains(seen) { watch.dockIntruders.append(seen) }
                    }
                }
            }
            for host in hosts { watch.hostAddresses[host, default: []].formUnion(GameConnections.addresses(of: host)) }
            if elapsed >= surviveSeconds { break }
            // A second at a time, so a Ctrl-C is answered within one.
            var slept = 0.0
            while slept < sampleSeconds, !isInterrupted() {
                Thread.sleep(forTimeInterval: min(1, sampleSeconds - slept))
                slept += 1
            }
            if isInterrupted() {
                watch.interrupted = true
                watch.watchedSeconds = Int(Date().timeIntervalSince(started))
                say("  Stopping: closing \(plan.name)…")
                break
            }
        }
        return watch
    }

    // MARK: - Judging

    static let staysUpTitle = "The game stays up, with no crash reporter and no Wine crash"
    static let onlineTitle = "The game's own process reaches its servers, with no TLS errors"

    static func judgeStaysUp(_ watch: Watch, wineLog: String, surviveSeconds: Int, name: String) -> VerificationCheck {
        func check(_ verdict: VerificationVerdict, _ detail: String, _ evidence: [String] = []) -> VerificationCheck {
            VerificationCheck(id: "stays-up", title: staysUpTitle, verdict: verdict, detail: detail, evidence: evidence)
        }
        let crashes = CrashSigns.crashLines(inWineLog: wineLog)
        if !watch.crashReporters.isEmpty {
            return check(.fail, "A crash reporter appeared after \(watch.watchedSeconds) s.",
                         watch.crashReporters + crashes.suffix(10))
        }
        if watch.interrupted, !watch.gameSeenRunning {
            return check(.couldNotCheck, "Verify was stopped after \(watch.watchedSeconds) s, before \(name)'s own process was seen.")
        }
        if !watch.gameSeenRunning {
            return check(.fail, "\(name)'s own process never appeared, though Play reported it started.", crashes.suffix(10).map { $0 })
        }
        if let after = watch.exitedAfter, after < surviveSeconds {
            return check(.fail, "\(name) stopped after \(after) s, short of the \(surviveSeconds) s it had to stay up.",
                         crashes.suffix(10).map { $0 })
        }
        if !crashes.isEmpty, watch.interrupted {
            return check(.fail, "Wine logged a crash before verify was stopped.", crashes.suffix(10).map { $0 })
        }
        if watch.interrupted {
            // Up so far is not up for the whole run: never a pass.
            return check(.couldNotCheck,
                         "\(name) was still up when verify was stopped after \(watch.watchedSeconds) s, short of the \(surviveSeconds) s it had to stay up.")
        }
        if !crashes.isEmpty {
            return check(.fail, "\(name) stayed up, but Wine logged a crash while it ran.", crashes.suffix(10).map { $0 })
        }
        return check(.pass, "\(name) stayed up for \(watch.watchedSeconds) s with no crash reporter and no crash in the Wine log.")
    }

    static func judgeOnline(_ watch: Watch, wineLog: String, plan: GamePlan) -> VerificationCheck {
        func check(_ verdict: VerificationVerdict, _ detail: String, _ evidence: [String] = []) -> VerificationCheck {
            VerificationCheck(id: "game-online", title: onlineTitle, verdict: verdict, detail: detail, evidence: evidence)
        }
        let tls = CrashSigns.tlsErrors(inWineLog: wineLog)
        let reached = watch.endpoints.filter { GameConnections.isPublic($0.address) }
        let seen = reached.map(\.description).sorted()
        if !tls.isEmpty {
            return check(.fail, "Wine logged \(tls.count) TLS or certificate error\(tls.count == 1 ? "" : "s") while the game ran, so at least one of its connections didn't get through.",
                         Array(tls.suffix(15)) + seen.prefix(10).map { "connected: \($0)" })
        }
        let hosts = plan.onlineHosts.map(GameConnections.hostName)
        if !hosts.isEmpty {
            let addresses = Set(reached.map { $0.address.lowercased() })
            let missing = hosts.filter { (watch.hostAddresses[$0] ?? []).isDisjoint(with: addresses) }
            if !missing.isEmpty {
                return check(.fail, "The game never connected to " + missing.joined(separator: ", ") + ".",
                             seen.map { "connected: \($0)" }
                                + missing.map { "\($0) resolves to: " + (watch.hostAddresses[$0] ?? []).sorted().joined(separator: ", ") })
            }
            return check(.pass, "The game connected to " + hosts.joined(separator: ", ") + ", with no TLS errors.", seen)
        }
        if isOffline(plan.facts.online) {
            return check(.pass, "The profile says this game has no online features, and no TLS errors were logged.")
        }
        guard !reached.isEmpty else {
            return check(.fail, "The game never connected to anything on the internet while it ran.")
        }
        return check(.pass, "The game connected to \(reached.count) server\(reached.count == 1 ? "" : "s") with no TLS errors. The profile names no `online_hosts`, so which servers they were isn't checked.", seen)
    }

    static let dockTitle = "Only the game is in the Dock, under its own name, never Wine or Steam"

    static func judgeDock(_ watch: Watch, name: String) -> VerificationCheck {
        func check(_ verdict: VerificationVerdict, _ detail: String, _ evidence: [String] = []) -> VerificationCheck {
            VerificationCheck(id: "dock", title: dockTitle, verdict: verdict, detail: detail, evidence: evidence)
        }
        guard watch.dockSamples > 0 else {
            return check(.couldNotCheck, watch.gameSeenRunning
                ? "macOS's list of running apps (lsappinfo) came back empty, so the Dock couldn't be read."
                : "The game was never seen running, so there was no Dock to read.")
        }
        if !watch.dockIntruders.isEmpty {
            return check(.fail, "The Dock showed \(watch.dockIntruders.count == 1 ? "an icon" : "icons") that shouldn't be there while \(name) ran.",
                         watch.dockIntruders)
        }
        guard watch.gameInDock else {
            return check(.fail, "\(name) never appeared in the Dock under its own name, from the app Cellar made for it.")
        }
        return check(.pass, "Across \(watch.dockSamples) look\(watch.dockSamples == 1 ? "" : "s") at the Dock, it showed \(name) under its own name and nothing of Wine or Steam.")
    }

    static let settingsTitle = "The bottle's settings match the profile, and the game runs in the Mac's language"

    static func judgeSettings(_ entries: [PerformanceSettings.Entry], language: LanguageChoice,
                              macLanguage: GameLanguage = .system()) -> VerificationCheck {
        var differences = entries.filter { $0.source == .bottle }
            .map { "\($0.setting.key) = \($0.value) is set for this bottle, over the profile" }
        if language.language != macLanguage {
            let whose = language.source == .thisGame ? "this game's language setting" : "the language setting for every game"
            differences.append("The game runs in \(language.language.nativeName) (\(whose)); the Mac is in \(macLanguage.nativeName)")
        }
        return VerificationCheck(
            id: "settings-match", title: settingsTitle, verdict: differences.isEmpty ? .pass : .fail,
            detail: differences.isEmpty
                ? "Nothing in the bottle overrides the profile, and the game runs in \(language.language.nativeName), the Mac's language."
                : "What was verified isn't the profile as it ships: \(differences.count) setting\(differences.count == 1 ? " differs" : "s differ").",
            evidence: differences)
    }

    /// Whether a profile's `online` describes a game with nothing online.
    static func isOffline(_ online: String?) -> Bool {
        guard let online = online?.lowercased().trimmingCharacters(in: .whitespaces), !online.isEmpty else { return false }
        return online.hasPrefix("none") || online.hasPrefix("offline") || online == "no"
    }

    static func judgeRuntime(before: CellarSandbox.Fingerprint, after: CellarSandbox.Fingerprint) -> VerificationCheck {
        let changes = after.changes(since: before)
        return VerificationCheck(
            id: "real-install-untouched", title: "The Windows runtime is exactly as it was before the run",
            verdict: changes.isEmpty ? .pass : .fail,
            detail: changes.isEmpty
                ? "Every runner file Cellar starts games from has the checksum it had before (\(before.files.count) files)."
                : "\(changes.count) runner file\(changes.count == 1 ? "" : "s") changed during the run. If Play repaired a damaged runtime, the runtime was damaged before this run.",
            evidence: changes)
    }

    static func judgeCleanExit(left: [RunnerProcesses.Entry], swept: [pid_t]) -> VerificationCheck {
        if !left.isEmpty {
            return VerificationCheck(id: "clean-exit", title: "After quitting, nothing of the bottle's Wine is left running",
                                     verdict: .fail, detail: "\(left.count) Wine process\(left.count == 1 ? " was" : "es were") still running 30 s after the game was closed.",
                                     evidence: left.map { "\($0.pid) \($0.path)" })
        }
        return VerificationCheck(id: "clean-exit", title: "After quitting, nothing of the bottle's Wine is left running",
                                 verdict: .pass,
                                 detail: swept.isEmpty ? "Everything closed by itself."
                                     : "Everything closed; Cellar's shutdown stopped \(swept.count) leftover process\(swept.count == 1 ? "" : "es"), as Play does.")
    }

    // MARK: - The process table

    static func processTable() -> String {
        Shell.run("/bin/ps", ["-axo", "pid=,command="]).stdout
    }

    /// The pids whose Windows command line names the game, from `ps -axo pid=,command=` — never a
    /// crash reporter or a Wine helper that only mentions the game's path.
    static func gamePids(inProcessList text: String, needles: [String]) -> [pid_t] {
        guard !needles.isEmpty else { return [] }
        let lowered = needles.map { $0.lowercased() }
        let reporters = Set(CrashSigns.crashReporters(inProcessList: text))
        return text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(of: " "), let pid = pid_t(line[..<space]) else { return nil }
            let command = line[line.index(after: space)...].lowercased()
            guard lowered.contains(where: { command.contains($0) }),
                  !ProcessWatch.impostors.contains(where: { command.contains($0) }),
                  !reporters.contains(line), !reporters.contains(String(raw)) else { return nil }
            return pid
        }
    }

    private func alreadyRunning() -> [String]? {
        let table = Self.processTable()
        let pids = Set(Self.gamePids(inProcessList: table, needles: plan.gameProcessNeedles))
        guard !pids.isEmpty else { return nil }
        return table.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in line.split(separator: " ").first.flatMap { pid_t($0) }.map(pids.contains) ?? false }
    }

    // MARK: - Closing it all

    private func closeEverything(_ plan: GamePlan) -> VerificationCheck {
        let table = Self.processTable()
        let doomed = Self.gamePids(inProcessList: table, needles: plan.gameProcessNeedles)
            + Self.pids(of: CrashSigns.crashReporters(inProcessList: table, extra: plan.crashProcesses))
        for pid in doomed { kill(pid, SIGTERM) }
        if !doomed.isEmpty { Thread.sleep(forTimeInterval: 5) }
        for pid in doomed where kill(pid, 0) == 0 { kill(pid, SIGKILL) }

        guard let wine = Game.wineRunner(plan), let install = RunnerManager.find(id: plan.runnerID) else {
            return VerificationCheck(id: "clean-exit", title: "After quitting, nothing of the bottle's Wine is left running",
                                     verdict: .couldNotCheck, detail: "The game's runner isn't installed.")
        }
        adapter.shutDownClient(plan, wine: wine)
        let swept = wine.shutDown()
        let root = RunnerProcesses.canonicalPath(install.root) + "/"
        var left: [RunnerProcesses.Entry] = []
        for _ in 0..<10 {
            left = RunnerProcesses.running().filter { $0.path.hasPrefix(root) && $0.pid != getpid() }
            if left.isEmpty { break }
            Thread.sleep(forTimeInterval: 3)
        }
        return Self.judgeCleanExit(left: left, swept: swept)
    }

    static func pids(of lines: [String]) -> [pid_t] {
        lines.compactMap { line in line.trimmingCharacters(in: .whitespaces).split(separator: " ").first.flatMap { pid_t($0) } }
    }

    // MARK: - Evidence

    /// The logs a game's Wine output can land in, whichever route started it.
    private func logFiles() -> [URL] {
        var names = ["game-\(plan.slug).log", "steam-\(plan.bottleName).log", "battlenet-\(plan.bottleName).log"]
        if let exe = plan.launchExe { names.append("game-\(((exe as NSString).lastPathComponent as NSString).deletingPathExtension).log") }
        return names.map { Paths.logs.appendingPathComponent($0) }
    }

    /// A picture of the screen while the game runs. Needs macOS's Screen Recording permission for
    /// whatever started `cellar`; without it there is simply no picture, and the report says so by
    /// listing none.
    private func takeScreenshot(run: Int, folder: URL) -> String? {
        let name = "run-\(run)-screen.png"
        let file = folder.appendingPathComponent(name)
        Shell.run("/usr/sbin/screencapture", ["-x", "-t", "png", file.path])
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        return size > 0 ? name : nil
    }

    private func environment() -> [String: String] {
        [
            "Cellar": CellarVersion.current,
            "runner": plan.runnerID,
            "backend": plan.backend,
            "macOS": SystemEnvironment.macOSVersionString,
            "chip": SystemEnvironment.chipBrand,
        ]
    }

    private func write(_ report: VerificationReport, to folder: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let json = try? encoder.encode(report) {
            try? json.write(to: folder.appendingPathComponent("report.json"), options: .atomic)
        }
        try? report.markdown.write(to: folder.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
    }

    static func folderName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss'Z'"
        return formatter.string(from: date)
    }
}
