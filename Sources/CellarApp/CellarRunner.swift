import Foundation
import CellarKit

/// Drives the `cellar` CLI as a subprocess so the GUI reuses every tested code path (setup, launch
/// with its auto-retry, steam add) instead of reimplementing them. Streams combined output.
@MainActor
final class CellarRunner: ObservableObject {
    /// Everything the CLI has printed, markers removed.
    @Published var log: String = ""
    @Published var busy: Bool = false
    @Published var busyTitle: String = ""
    /// How far a launch has got, when the running command is one that reports it. Kept after the
    /// command ends, so the launch window can show how it finished rather than going blank.
    @Published private(set) var stage: LaunchStage?
    /// The exit status of the last command, nil while one is running.
    @Published private(set) var exitCode: Int32?
    @Published private(set) var phase: Phase = .idle
    /// How many times the launch has been attempted. Counted from the stages rather than scraped
    /// out of the CLI's prose, so the launch window can say "second try" in its own words instead
    /// of quoting a line about the D3DMetal startup race at someone who wants to play a game.
    @Published private(set) var attempt: Int = 0

    /// A launch does not end when the game starts: `cellar launch` stays alive for the whole session
    /// so it can close the layer afterwards. Without this distinction the app spends a two-hour play
    /// session claiming to be "Launching".
    enum Phase { case idle, working, playing }

    /// Resolved on first use, never in `init`.
    ///
    /// `Shell.which` spawns a subprocess. SwiftUI creates a `@StateObject` lazily, during the first
    /// evaluation of the view graph — so doing this in `init` meant forking a process from inside
    /// `NSHostingView.layout()`, and this app aborts in AttributeGraph when layout re-enters
    /// (skills/swift.md). Deferring it keeps view-graph evaluation free of side effects.
    private lazy var binary: String = Shell.which("cellar") ?? "\(NSHomeDirectory())/.local/bin/cellar"

    /// The running command, so it can be called off.
    private var process: Process?
    /// Output received but not yet ended by a newline — held back so a marker split across two
    /// reads is still recognised. Shown in the log regardless, or a `\r`-only progress line
    /// (DepotDownloader's) would look like a stall.
    private var pending: String = ""
    private var committed: String = ""
    /// Whether the running command reports stage markers (only `launch --machine-progress` does).
    private var readsStages = false

    init() {}

    var binaryExists: Bool { FileManager.default.isExecutableFile(atPath: binary) }

    /// Put a line in the activity log without running anything — for the steps Cellar hands back
    /// to the player (a download that needs a real terminal for its Steam Guard prompt).
    func note(_ message: String) {
        committed += "\n\(message)\n"
        log = committed + pending
    }

    /// `observe` sees each chunk of output as it arrives, for a caller that has to react to
    /// something mid-run rather than after exit — the Steam QR challenge is the reason it exists.
    ///
    /// `stages` says this command was asked to report its steps. Only then is the output read for
    /// markers: every other command's output belongs to the player verbatim, and a line that
    /// happened to start with the marker prefix should not vanish from the activity log.
    func run(_ args: [String], title: String, stages: Bool = false,
             observe: (@MainActor (String) -> Void)? = nil,
             then: (@MainActor () -> Void)? = nil) {
        guard !busy else { return }
        busy = true; busyTitle = title; phase = .working
        stage = nil; attempt = 0; exitCode = nil; cancelled = false; launchingSlug = nil
        readsStages = stages

        // Redact once, use everywhere. `args` can carry a credential the player just pasted — the
        // GOG sign-in hands this method their one-time OAuth code — and it reaches two places from
        // here: the on-screen activity pane (which a player screenshots into a bug report) and the
        // rolling log (which `cellar logs export` ships). The subprocess redacts its own
        // invocation; this is the app's separate copy of the same command line.
        let shown = "cellar " + Diagnostics.redactCommandLine(args).text
        committed += "\n$ \(shown)\n"
        log = committed + pending

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
                guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in self.absorb(s); observe?(s) }
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
                    self.absorb("\nCellar's command-line helper isn't at \(helperPath).\n"
                        + "Reinstall Cellar, or run: sh Scripts/install-app.sh\n")
                    self.busy = false
                    then?()
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
                self.absorb("\n(exit \(process.terminationStatus))\n")
                self.process = nil
                self.busy = false
                self.phase = .idle
                self.exitCode = process.terminationStatus
                then?()
            }
        }
    }

    /// Start a game, asking the CLI to report its steps so the launch window can follow along.
    ///
    /// Its own method rather than a `run(["launch", …])` at the call site: a launch is the one
    /// command with a window watching it, and the flag that feeds that window should not be
    /// something a future caller has to remember.
    func launch(slug: String, showHUD: Bool, then: (@MainActor () -> Void)? = nil) {
        guard !busy else { return }
        run(["launch", slug, "--machine-progress"] + (showHUD ? ["--hud"] : []),
            title: "Launching", stages: true, then: then)
        launchingSlug = slug
    }

    /// The game currently being launched, if the running command is a launch.
    @Published private(set) var launchingSlug: String?

    /// Whether the last command was called off rather than failing on its own — a non-zero exit the
    /// player asked for is not an error to report back to them.
    @Published private(set) var cancelled: Bool = false

    /// Stop the running command. Anything it already opened — Steam, Battle.net, the game itself —
    /// stays open; Cellar only stops waiting on it, and says so where the button lives.
    func cancel() {
        guard busy else { return }
        cancelled = true
        process?.terminate()
    }

    // MARK: - Reading the output

    /// Split output into lines, lift the stage markers out, and leave the rest for the player.
    private func absorb(_ chunk: String) {
        pending += chunk
        while let newline = pending.firstIndex(of: "\n") {
            let line = String(pending[pending.startIndex..<newline])
            pending = String(pending[pending.index(after: newline)...])
            if readsStages, let reached = LaunchMarker.stage(in: line) {
                stage = reached
                if reached == .starting { attempt += 1 }
                if reached == .playing { phase = .playing }
            } else {
                committed += line + "\n"
            }
        }
        log = committed + pending
    }
}
