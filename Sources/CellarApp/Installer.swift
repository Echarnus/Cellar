import AppKit
import SwiftUI
import CellarKit

// The installer's three jobs that only the app can do: getting the shared parts in the background on
// first launch, moving itself out of the disk image, and taking itself off the Mac again. The
// deciding lives in CellarKit (`Preparation`, `InstallLocation`, `Reset` + `SaveGames`); this file
// only asks and shows.

// MARK: - Getting ready in the background

/// `cellar prepare`, run by the app on launch until everything every game shares is on the Mac.
///
/// It starts while the player is reading the welcome tour, so by the time they press Install the
/// runtime and the Steam client are already here. It runs on its own `ActivityStore`, not the
/// library's, so it never holds the Play and Install buttons — a game set up meanwhile waits for it
/// in the CLI (`SetupLock`) and says so in its own activity log.
///
/// One instance, owned by `AppModel` and handed to the views that show it.
@MainActor
@Observable
final class RuntimePreparation {

    enum State: Equatable {
        case idle
        /// The latest line `cellar prepare` printed, for the footer.
        case working(String)
        case ready
        /// It stopped early; each part will be fetched when a game first needs it, so this is a
        /// note, not an error.
        case incomplete
    }
    private(set) var state: State = .idle

    /// The player's choice in Settings. On by default: the whole point is that a first game should
    /// not open on a 3 GB wait, and the welcome tour says it is happening.
    static let defaultsKey = "prepareAheadOfTime"
    var isEnabled: Bool = UserDefaults.standard.object(forKey: RuntimePreparation.defaultsKey) as? Bool ?? true {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.defaultsKey)
            if isEnabled { startIfNeeded() } else { cancel() }
        }
    }

    @ObservationIgnored private let runner = ActivityStore()

    var isWorking: Bool { if case .working = state { return true } else { return false } }

    /// Starts when it is switched on, something is missing, and there is a CLI to run. Called after
    /// the first window is up, never from inside a view update.
    func startIfNeeded() {
        guard isEnabled, !isWorking, runner.binaryExists else { return }
        guard !Preparation.isComplete else { state = .ready; return }
        state = .working("Starting…")
        runner.run(.prepare, title: String(localized: "Getting Cellar ready"), observe: { [weak self] line in
            let text = line.trimmingCharacters(in: .whitespaces)
            // The CLI drops colour when its output is a pipe; strip escape codes anyway, so a
            // stray one never reaches the footer.
            let plain = text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
            guard !plain.isEmpty, !plain.hasPrefix("$ "), !plain.hasPrefix("(exit") else { return }
            self?.state = .working(plain)
        }, then: { [weak self] in
            guard let self else { return }
            self.state = Preparation.isComplete ? .ready : .incomplete
        })
    }

    func cancel() {
        guard isWorking else { return }
        runner.cancel()
        state = .incomplete
    }
}

/// The library's footer line while preparation runs: a small spinner and what is happening, with
/// the why on hover. Nothing at all once it is done — there is nothing left to say.
struct PreparationStatus: View {
    let preparation: RuntimePreparation

    var body: some View {
        if case .working(let line) = preparation.state {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Getting ready: \(line)")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .help("Cellar is downloading the Windows runtime and Steam client every game shares, so your first game starts sooner. You can play while it runs; a game that needs them waits for it.")
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Moving out of the disk image

@MainActor
enum MoveToApplications {
    /// If Cellar is running from the disk image (or from App Translocation's copy of it), offer to
    /// move it into Applications and restart from there. Returns true when it is relaunching, so
    /// the caller stops setting up a window that is about to go away.
    static func offerIfNeeded() -> Bool {
        let location = InstallLocation.of(bundlePath: Bundle.main.bundlePath)
        guard location.shouldOfferMove,
              ProcessInfo.processInfo.environment["CELLAR_DIAG"] == nil else { return false }

        let destination = InstallLocation.moveDestination()
        let alert = NSAlert()
        alert.messageText = String(localized: "Move Cellar to your Applications folder?")
        let folder = destination.deletingLastPathComponent().path
        alert.informativeText = String(localized: """
            Cellar is running from the disk image, so it would disappear when the image is ejected \
            and could not update itself. Moving it copies Cellar to \(folder) and opens it from there.
            """)
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        NSApp.bringToFront()
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) {
                // An older Cellar there goes to the Bin, not into oblivion — the player can still
                // get it back.
                try fm.trashItem(at: destination, resultingItemURL: nil)
            }
            // ditto, not copyItem: it keeps the bundle's signature, extended attributes and the
            // framework symlinks codesign sealed.
            let copy = Shell.run("/usr/bin/ditto", [Bundle.main.bundlePath, destination.path])
            guard copy.succeeded else {
                throw CellarError.ioFailure("Copying Cellar failed: \(copy.stderr)")
            }
        } catch {
            let failure = NSAlert()
            failure.messageText = String(localized: "Cellar couldn't be moved")
            failure.informativeText = error.localizedDescription + "\n\n" + String(localized: """
                Drag Cellar from the disk image onto the Applications folder instead. \
                For now it keeps running from here.
                """)
            failure.runModal()
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    let failure = NSAlert()
                    failure.messageText = String(localized: "Cellar was moved but couldn't be opened")
                    failure.informativeText = String(localized: "Open it from \(destination.path). (\(error.localizedDescription))")
                    failure.runModal()
                }
                NSApp.terminate(nil)
            }
        }
        return true
    }
}

// MARK: - Uninstalling

@MainActor
enum CellarUninstaller {
    /// Cellar › Uninstall Cellar…: measure, ask once with the save-game choice on the same dialog,
    /// then run `cellar uninstall-cellar` and quit. Measuring walks every bottle, so it happens off
    /// the main thread with the menu already closed.
    static func begin(preparation: RuntimePreparation) {
        Task {
            let summary = await Task.detached(priority: .userInitiated) { () -> (Int64, Int64, Int) in
                let items = Reset.plan(includingCellarItself: true)
                let saves = SaveGames.locate()
                return (Reset.totalBytes(items), saves.reduce(0) { $0 + $1.bytes }, saves.count)
            }.value
            confirm(totalBytes: summary.0, saveBytes: summary.1, saveCount: summary.2, preparation: preparation)
        }
    }

    private static func confirm(totalBytes: Int64, saveBytes: Int64, saveCount: Int,
                                preparation: RuntimePreparation) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Uninstall Cellar?")
        let total = Reset.humanSize(totalBytes)
        alert.informativeText = String(localized: """
            This removes Cellar, its command-line tool, every bottle, the Wine runtime, the Windows \
            Steam client and the games installed in it — \(total) in all. Games you own stay yours: \
            reinstall Cellar and they download again from their store.
            """)
        let keep = NSButton(checkboxWithTitle: saveCount == 0
                            ? String(localized: "Keep my save games (none found inside Cellar)")
                            : String(localized: "Keep my save games (\(Reset.humanSize(saveBytes))) — copied to Documents first"),
                            target: nil, action: nil)
        keep.state = .on
        keep.isEnabled = saveCount > 0
        alert.accessoryView = keep
        alert.addButton(withTitle: String(localized: "Uninstall"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.bringToFront()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        run(keepSaves: keep.state == .on && saveCount > 0, preparation: preparation)
    }

    private static func run(keepSaves: Bool, preparation: RuntimePreparation) {
        preparation.cancel()
        let runner = ActivityStore()
        // Deleting a games library takes a while; a window that says so beats an app that seems
        // to have done nothing.
        let progress = progressWindow(keepSaves: keepSaves)
        runner.run(.uninstallCellar(keepSaves: keepSaves), title: String(localized: "Uninstalling Cellar"), then: {
            progress.close()
            let succeeded = runner.exitCode == 0
            let done = NSAlert()
            if succeeded {
                done.messageText = String(localized: "Cellar is uninstalled")
                done.informativeText = keepSaves
                    ? String(localized: "Your save games are in Documents › Cellar Saved Games. Cellar will now quit.")
                    : String(localized: "Nothing of it is left on this Mac. Cellar will now quit.")
                if keepSaves { done.addButton(withTitle: String(localized: "Show Save Games")) }
                done.addButton(withTitle: String(localized: "Quit"))
            } else {
                done.alertStyle = .warning
                done.messageText = String(localized: "Cellar couldn't remove everything")
                done.informativeText = String(localized: "A running game holds some files open. Quit it, then choose Uninstall Cellar… again. What happened:")
                    + "\n\n" + runner.log.split(separator: "\n").suffix(6).joined(separator: "\n")
                done.addButton(withTitle: String(localized: "OK"))
            }
            let answer = done.runModal()
            guard succeeded else { return }
            if keepSaves, answer == .alertFirstButtonReturn {
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Documents/Cellar Saved Games", isDirectory: true))
            }
            // cfprefsd holds the app's settings in memory and would write them back; tell it
            // they are gone as well as deleting the file.
            if let id = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: id)
            }
            // Straight out, not NSApp.terminate: the normal quit path writes to Cellar's log
            // folder, which would put back the folder the uninstall just removed.
            exit(0)
        })
    }

    private static func progressWindow(keepSaves: Bool) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 96),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Uninstalling Cellar"
        window.isReleasedWhenClosed = false
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)
        let label = NSTextField(wrappingLabelWithString: keepSaves
            ? "Copying your save games, then removing Cellar and everything it downloaded…"
            : "Removing Cellar and everything it downloaded…")
        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack
        window.center()
        window.makeKeyAndOrderFront(nil)
        return window
    }
}
