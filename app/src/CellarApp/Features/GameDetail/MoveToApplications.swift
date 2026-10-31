import CellarDomain
import AppKit
import SwiftUI
import CellarData

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
