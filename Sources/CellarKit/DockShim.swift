import Foundation

/// Keeps a bottle's storefront client out of the Dock.
///
/// Wine gives a Dock icon to every Windows process that shows a window. For a game that is right —
/// it is the thing the player started. For Steam or Battle.net it is not: Cellar stands those up on
/// the player's behalf, and a second icon beside Cellar's advertises plumbing nobody asked to see.
/// Wine has no setting for this, so Cellar inserts a small library into the client's processes that
/// turns their "give me a Dock icon" into "make me an accessory" — windows, focus and keyboard all
/// intact, only the Dock tile and the ⌘-Tab entry gone. `Shim/cellar-dock-shim.c` is the library and
/// explains the mechanism.
///
/// The shim is built by `Scripts/build-dock-shim.sh` and installed beside the `cellar` binary the
/// same way the profile database is. If it is missing — a partial build, an old install — every
/// launch behaves exactly as it did before, with the client's icon back in the Dock. That is the
/// honest failure: a cosmetic feature must never be able to stop a game from starting.
public enum DockShim {
    static let libraryName = "cellar-dock-shim.dylib"

    /// Where an installed Cellar keeps the shim, most specific first. Mirrors the layout
    /// `Paths.bundledProfiles` uses, plus the build directory so a repo checkout works too.
    public static var libraryURL: URL? {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["CELLAR_DOCK_SHIM"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }
        // Cellar.app/Contents/Resources/cellar-dock-shim.dylib
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(libraryName))
        }
        if let argv0 = ProcessInfo.processInfo.arguments.first {
            let binDir = URL(fileURLWithPath: argv0).resolvingSymlinksInPath().deletingLastPathComponent()
            // An installed CLI: <prefix>/bin/cellar next to <prefix>/share/cellar/<shim>.
            candidates.append(binDir.appendingPathComponent("../share/cellar/\(libraryName)").standardizedFileURL)
            // A development build: beside .build/release/cellar.
            candidates.append(binDir.appendingPathComponent(libraryName))
        }
        // The default output of Scripts/build-dock-shim.sh, run from the repo root.
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/\(libraryName)"))
        candidates.append(Paths.appSupport.appendingPathComponent(libraryName))

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Environment that keeps `processNames` (Windows executable names, e.g. `steam.exe`) out of the
    /// Dock. Every other process the launch produces — the game above all — is untouched, so a name
    /// Cellar does not know about keeps its icon rather than silently losing it.
    ///
    /// Returns nothing when there is nothing to hide or the shim is not installed; the caller then
    /// launches exactly as it always did.
    public static func environment(hiding processNames: [String]) -> [String: String] {
        guard !processNames.isEmpty, let library = libraryURL else { return [:] }
        return [
            "DYLD_INSERT_LIBRARIES": library.path,
            "CELLAR_DOCK_HIDE": processNames.joined(separator: ","),
        ]
    }

    /// Environment that hides `store`'s client. `dock == .visible` returns nothing, for the screens
    /// where the client *is* what the player asked for and needs to be findable in the Dock.
    public static func environment(for store: GameStore, dock: DockPresence) -> [String: String] {
        guard dock == .hidden else { return [:] }
        return environment(hiding: store.descriptor.clientProcessNames)
    }
}

/// Whether a store client Cellar is about to start should appear in the Dock.
///
/// The two cases are genuinely different, and the difference is the player's intent. Starting a
/// game runs the client as scaffolding — it is `.hidden`, and the Dock shows what the player thinks
/// is running: Cellar, then the game. Choosing "Open Steam" makes the client the thing on screen —
/// it is `.visible`, because a window the player has to come back to (sign in, install, a store
/// page) needs a Dock icon and a ⌘-Tab entry to come back *to*.
public enum DockPresence: Sendable {
    case hidden
    case visible
}
