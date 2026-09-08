import Foundation
import CellarKit

/// Drives the `cellar` CLI as a subprocess so the GUI reuses every tested code path (setup, launch
/// with its auto-retry, steam add) instead of reimplementing them. Streams combined output.
@MainActor
final class CellarRunner: ObservableObject {
    @Published var log: String = ""
    @Published var busy: Bool = false
    @Published var busyTitle: String = ""

    /// Resolved on first use, never in `init`.
    ///
    /// `Shell.which` spawns a subprocess. SwiftUI creates a `@StateObject` lazily, during the first
    /// evaluation of the view graph — so doing this in `init` meant forking a process from inside
    /// `NSHostingView.layout()`, and this app aborts in AttributeGraph when layout re-enters
    /// (skills/swift.md). Deferring it keeps view-graph evaluation free of side effects.
    private lazy var binary: String = Shell.which("cellar") ?? "\(NSHomeDirectory())/.local/bin/cellar"

    init() {}

    var binaryExists: Bool { FileManager.default.isExecutableFile(atPath: binary) }

    /// Put a line in the activity log without running anything — for the steps Cellar hands back
    /// to the player (a download that needs a real terminal for its Steam Guard prompt).
    func note(_ message: String) {
        log += "\n\(message)\n"
    }

    /// `observe` sees each chunk of output as it arrives, for a caller that has to react to
    /// something mid-run rather than after exit — the Steam QR challenge is the reason it exists.
    func run(_ args: [String], title: String, observe: (@MainActor (String) -> Void)? = nil,
             then: (@MainActor () -> Void)? = nil) {
        guard !busy else { return }
        busy = true; busyTitle = title

        // Redact once, use everywhere. `args` can carry a credential the player just pasted — the
        // GOG sign-in hands this method their one-time OAuth code — and it reaches two places from
        // here: the on-screen activity pane (which a player screenshots into a bug report) and the
        // rolling log (which `cellar logs export` ships). The subprocess redacts its own
        // invocation; this is the app's separate copy of the same command line.
        let shown = "cellar " + Diagnostics.redactCommandLine(args).text
        log += "\n$ \(shown)\n"

        Task.detached { [binary] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in self.log += s; observe?(s) }
            }
            do {
                try process.run()
            } catch {
                // The CLI is how the app does everything — if it can't be started, the player sees
                // a button that does nothing, so make sure the reason is on record.
                // The same string on screen as in the log: this path runs through the player's home
                // folder, and the activity pane ends up in screenshots.
                let helperPath = Diagnostics.redact(binary)
                CellarLog.error(.app, "Could not run the cellar CLI at "
                    + "\(helperPath): \(CellarLog.describe(error))")
                await MainActor.run {
                    self.log += "\nCellar's command-line helper isn't at \(helperPath).\n"
                        + "Reinstall Cellar, or run: sh Scripts/install-app.sh\n"
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
                self.log += "\n(exit \(status))\n"
                self.busy = false
                then?()
            }
        }
    }
}
