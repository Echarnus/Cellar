import CellarDomain
import Foundation
import Observation
import CellarData

/// What Cellar is doing right now, for every window at once.
///
/// Drives the `cellar` CLI as a subprocess so the GUI reuses every tested code path (setup, launch
/// with its auto-retry, steam add) instead of reimplementing them. Streams combined output.
///
/// There is one of these for the player's actions, made by `AppModel` and handed to every window
/// (docs/APP-ARCHITECTURE.md). It used to be one per window, so "busy" was per window: Settings
/// could start a sign-in while the library was mid-install, and the library never learned a
/// sign-in was running. Background work that must never hold the Play button — `RuntimePreparation`
/// — keeps an instance of its own on purpose.
@MainActor
@Observable
final class ActivityStore {
    /// The end of what the CLI has printed, markers removed (`LogTail`). Published a few times a
    /// second at most: a download prints faster than anyone reads, and every change to this is a
    /// layout of the text on screen.
    private(set) var log: String = ""
    var busy: Bool = false
    var busyTitle: String = ""
    /// How far a launch has got, when the running command is one that reports it. Kept after the
    /// command ends, so the launch window can show how it finished rather than going blank.
    private(set) var stage: LaunchStage?
    /// The exit status of the last command, nil while one is running.
    private(set) var exitCode: Int32?
    private(set) var phase: Phase = .idle
    /// How many times the launch has been attempted. Counted from the stages rather than scraped
    /// out of the CLI's prose, so the launch window can say "second try" in its own words instead
    /// of quoting a line about the D3DMetal startup race at someone who wants to play a game.
    private(set) var attempt: Int = 0
    /// Where an install stands, when the running command is `install --events`. Nil for
    /// every other command, and until the install has said which phase it is in.
    private(set) var installProgress: InstallProgress?
    /// The game being installed, so only its page draws the bar.
    private(set) var installingSlug: String?

    /// A launch does not end when the game starts: `cellar launch` stays alive for the whole session
    /// so it can close the layer afterwards. Without this distinction the app spends a two-hour play
    /// session claiming to be "Launching".
    enum Phase { case idle, working, playing }

    /// Resolved on first use — which is inside a view body (the library footer asks whether the CLI
    /// exists), so it must never start a process.
    ///
    /// It used to be `Shell.which`, and `waitUntilExit()` spins the main run loop. From inside a
    /// SwiftUI update on macOS 27 that leaves the hosting view's graph unable to apply any later
    /// change: the library refreshed, logged "4 shown", and the window kept drawing "Sign in" and
    /// "0 games" forever. `Shell.locate` reads PATH with the file system instead.
    ///
    /// The CLI inside Cellar.app comes first: it was built with this app, and an app update
    /// replaces the two together. One on PATH would keep driving the new app with an old engine.
    private var binary: String {
        if let resolvedBinary { return resolvedBinary }
        let found = Bundle.main.path(forAuxiliaryExecutable: "cellar")
            ?? Shell.locate("cellar") ?? "\(NSHomeDirectory())/.local/bin/cellar"
        resolvedBinary = found
        return found
    }
    /// Held by hand rather than as a `lazy var`, which `@Observable` does not take.
    @ObservationIgnored private var resolvedBinary: String?

    /// The running command, so it can be called off.
    @ObservationIgnored private var process: Process?
    /// The running command's output, assembled into lines. What has not ended in a newline yet is
    /// held back, so a marker split across two reads is still recognised, and shown as it stands.
    @ObservationIgnored private var lines = OutputLines()
    /// The lines the log shows: the last thousand, with a count of the rest.
    @ObservationIgnored private var tail = LogTail(limit: 1_000)
    /// Whether a publish of `log` and `installProgress` is already on its way.
    @ObservationIgnored private var publishPending = false
    /// The newest install progress, waiting for the next publish.
    @ObservationIgnored private var latestProgress: InstallProgress?
    /// How often, at most, the log and the bar are redrawn while a command runs.
    static let publishInterval: Duration = .milliseconds(250)
    /// Called each time a command ends and the runner is free, after the command's own `then`. The
    /// downloads queue starts its next game from here (`DownloadsViewModel`).
    @ObservationIgnored var whenIdle: (@MainActor () -> Void)?
    /// Whether the running command reports progress events (`CellarCommand.reportsStages`).
    @ObservationIgnored private var readsStages = false
    /// The running command's line observer, if it asked for one.
    @ObservationIgnored private var lineObserver: (@MainActor (String) -> Void)?

    init() {}

    var binaryExists: Bool { FileManager.default.isExecutableFile(atPath: binary) }

    /// Put a line in the activity log without running anything — for the steps Cellar hands back
    /// to the player (a download that needs a real terminal for its Steam Guard prompt).
    func note(_ message: String) {
        tail.append("")
        tail.append(message)
        publish()
    }

    /// `observe` sees the output **one complete line at a time**, as it arrives, for a caller that
    /// has to react to something mid-run rather than after exit — the Steam QR challenge is the
    /// reason it exists.
    ///
    /// Whole lines, not raw reads: a pipe breaks wherever it likes, so handing a caller the chunks
    /// meant a QR row straddling a read arrived as two short rows and the matrix never squared up.
    /// `absorb` already assembles lines for the activity log, so the observer rides along with it.
    ///
    /// Only a command that reports its steps (`CellarCommand.reportsStages`) has its output read
    /// for markers: every other command's output belongs to the player verbatim, and a line that
    /// happened to start with the marker prefix should not vanish from the activity log.
    func run(_ command: CellarCommand, title: String,
             observe: (@MainActor (String) -> Void)? = nil,
             then: (@MainActor () -> Void)? = nil) {
        run(arguments: command.arguments, title: title, stages: command.reportsStages,
            game: command.game, observe: observe, then: then)
    }

    private func run(arguments args: [String], title: String, stages: Bool, game: String?,
                     observe: (@MainActor (String) -> Void)?,
                     then: (@MainActor () -> Void)?) {
        guard !busy else { return }
        busy = true; busyTitle = title; phase = .working; workingOn = game
        stage = nil; attempt = 0; exitCode = nil; cancelled = false; launchingSlug = nil
        installProgress = nil; installingSlug = nil; latestProgress = nil
        lines = OutputLines()
        readsStages = stages
        lineObserver = observe

        // Redact once, use everywhere. `args` can carry a credential the player just pasted — the
        // GOG sign-in hands this method their one-time OAuth code — and it reaches two places from
        // here: the on-screen activity pane (which a player screenshots into a bug report) and the
        // rolling log (which `cellar logs export` ships). The subprocess redacts its own
        // invocation; this is the app's separate copy of the same command line.
        let shown = "cellar " + Diagnostics.redactCommandLine(args).text
        tail.append("")
        tail.append("$ \(shown)")
        publish()
        let inbox = OutputInbox()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        self.process = process
        let binaryPath = binary

        Task.detached {
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, inbox.put(data) else { return }
                Task { @MainActor in self.drain(inbox) }
            }
            do {
                try process.run()
            } catch {
                // The CLI is how the app does everything — if it can't be started, the player sees
                // a button that does nothing, so make sure the reason is on record.
                // The same string on screen as in the log: this path runs through the player's home
                // folder, and the activity pane ends up in screenshots.
                let helperPath = Diagnostics.redact(binaryPath)
                CellarLog.error(.app, "Could not run the cellar CLI at "
                    + "\(helperPath): \(CellarLog.describe(error))")
                await MainActor.run {
                    self.absorb(["", "Cellar's command-line helper isn't at \(helperPath).",
                                 "Reinstall Cellar, or run: sh app/Scripts/install-app.sh"])
                    self.publish()
                    self.busy = false
                    self.phase = .idle
                    then?()
                    self.whenIdle?()
                }
                return
            }
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            let status = process.terminationStatus
            if status != 0 {
                CellarLog.debug(.app, "\(shown) exited with \(status).")
            }
            await MainActor.run {
                // Absorb first — that flushes any last line without a newline through the observer
                // — then let the observer go, so it cannot outlive the command that installed it.
                self.drain(inbox)
                if let last = self.lines.finish() { self.absorb([last]) }
                self.absorb(["", "(exit \(status))"])
                self.lineObserver = nil
                self.process = nil
                self.busy = false
                self.phase = .idle
                self.latestProgress = nil
                self.publish()
                self.installProgress = nil
                self.installingSlug = nil
                self.exitCode = status
                then?()
                self.whenIdle?()
            }
        }
    }

    /// Start a game, asking the CLI to report its steps so the launch window can follow along.
    ///
    /// Its own method rather than a `run(["launch", …])` at the call site: a launch is the one
    /// command with a window watching it, and the flag that feeds that window should not be
    /// something a future caller has to remember.
    ///
    /// `backend` tries another graphics backend for this launch; the CLI keeps it if the game comes up.
    func launch(slug: String, showHUD: Bool, backend: GraphicsBackend? = nil,
                then: (@MainActor () -> Void)? = nil) {
        guard !busy else { return }
        run(.launch(slug: slug, showHUD: showHUD, backend: backend), title: String(localized: "Launching"), then: then)
        launchingSlug = slug
        launchShowsHUD = showHUD
    }

    /// Whether the last launch asked for the HUD, so a retry from the launch window asks again.
    private(set) var launchShowsHUD = false

    /// Install a game, asking the CLI to report its phases so the page can draw a progress bar.
    /// Its own method for the same reason `launch` is: the flag that feeds the bar should not be
    /// something a call site has to remember.
    func install(slug: String, title: String, then: (@MainActor () -> Void)? = nil) {
        guard !busy else { return }
        run(.install(slug: slug, machineProgress: true), title: title, then: then)
        installingSlug = slug
    }

    /// Run a CLI command beside the runner rather than on it — no activity log, no busy state — and
    /// wait for it. For the background update check only: it must not take the one runner (and every
    /// Play button with it) away from the player, yet it talks to Steam, so it still goes through
    /// the CLI like every other networked action instead of running inside the app.
    func runBeside(_ command: CellarCommand) async -> Int32 {
        let path = binary
        let args = command.arguments
        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return -1 }
            process.waitUntilExit()
            return process.terminationStatus
        }.value
    }

    /// Bring a game Cellar downloaded up to Steam's current build, with the same bar as Install —
    /// a patch can be gigabytes, and a spinner is no answer to "how long".
    func update(slug: String, name: String, then: (@MainActor () -> Void)? = nil) {
        guard !busy else { return }
        run(.update(slug: slug), title: String(localized: "Updating \(name)"), then: then)
        installingSlug = slug
    }

    /// The game currently being launched, if the running command is a launch.
    private(set) var launchingSlug: String?

    /// The game the running command works on, nil for work that belongs to Cellar as a whole.
    private(set) var workingOn: String?

    /// The runner as a game's page sees it (`GamePageStatus`), so each page says only what is
    /// happening to its own game.
    var forPages: GamePageStatus.Runner {
        GamePageStatus.Runner(busy: busy, game: workingOn, title: busyTitle,
                              launching: launchingSlug != nil, installing: installingSlug != nil,
                              playing: phase == .playing)
    }

    /// Whether the last command was called off rather than failing on its own — a non-zero exit the
    /// player asked for is not an error to report back to them.
    private(set) var cancelled: Bool = false

    /// Stop the running command. Anything it already opened — Steam, Battle.net, the game itself —
    /// stays open; Cellar only stops waiting on it, and says so where the button lives.
    func cancel() {
        guard busy else { return }
        cancelled = true
        process?.terminate()
    }

    // MARK: - Reading the output

    /// Take what the pipe has delivered, as whole lines.
    private func drain(_ inbox: OutputInbox) {
        absorb(lines.lines(in: inbox.take()))
    }

    /// Lift the progress events out of `newLines` (`CommandEvent`), and keep the rest for the player.
    private func absorb(_ newLines: [String]) {
        for line in newLines {
            if readsStages, let event = CommandEvent.parse(line) {
                switch event {
                case .install(let progress):
                    latestProgress = progress
                case .stage(let reached):
                    stage = reached
                    if reached == .starting { attempt += 1 }
                    if reached == .playing { phase = .playing }
                    // The game is gone; what is left is Cellar closing up behind it. Still busy —
                    // Play waits for the teardown — but no longer "Playing".
                    if reached == .closing {
                        phase = .working
                        busyTitle = String(localized: "Closing down")
                    }
                }
            } else if readsStages, CommandEvent.isEvent(line) {
                // From a newer CLI than this app knows: not for the player to read as JSON.
                continue
            } else {
                // The observer sees the line as printed — the Accounts QR panel is drawn from it —
                // but the log never keeps a row of Steam's sign-in code (`isSignInCodeRow`).
                lineObserver?(line)
                if Diagnostics.isSignInCodeRow(line) {
                    if tail.kept.last != Diagnostics.signInCodeRemoved {
                        tail.append(Diagnostics.signInCodeRemoved)
                    }
                } else {
                    tail.append(line)
                }
            }
        }
        schedulePublish()
    }

    /// Redraw the log and the bar soon, once, however many reads arrive before then.
    private func schedulePublish() {
        guard !publishPending else { return }
        publishPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.publishInterval)
            self?.publish()
        }
    }

    /// Hand the views the log and the progress as they stand now.
    private func publish() {
        publishPending = false
        // A partial line can be half a QR row; it is shown once it is whole, or not at all.
        let partial = Diagnostics.isSignInCodeRow(lines.partial) ? "" : lines.partial
        let text = tail.text(partial: partial)
        if text != log { log = text }
        if busy, installProgress != latestProgress { installProgress = latestProgress }
    }
}
