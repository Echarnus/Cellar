import CellarDomain
import AppKit
import SwiftUI
import CellarKit

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
        window.title = String(localized: "Uninstalling Cellar")
        window.isReleasedWhenClosed = false
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)
        let label = NSTextField(wrappingLabelWithString: keepSaves
            ? String(localized: "Copying your save games, then removing Cellar and everything it downloaded…")
            : String(localized: "Removing Cellar and everything it downloaded…"))
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
