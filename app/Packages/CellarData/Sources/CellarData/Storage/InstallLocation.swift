import CellarDomain
import Foundation

/// Where a running Cellar.app is, and whether it ought to be somewhere else.
///
/// A player who double-clicks Cellar inside the disk image instead of dragging it out runs it from
/// a read-only volume that vanishes on eject — or, because the download is quarantined, from the
/// random read-only path macOS's App Translocation mounts it at. Either way the app works today
/// and is gone tomorrow, and the updater cannot replace a copy it cannot write to. So the app
/// offers to move itself into Applications, the step the DMG window asks for, done for them.
public enum InstallLocation: Equatable, Sendable {
    /// In an Applications folder, or anywhere else writable the player chose. Leave it be.
    case installed
    /// On a mounted disk image (`/Volumes/…`).
    case diskImage
    /// Under App Translocation: macOS copied a quarantined app to a temporary read-only mount.
    case translocated

    public static func of(bundlePath path: String) -> InstallLocation {
        if path.contains("/AppTranslocation/") { return .translocated }
        if path.hasPrefix("/Volumes/") { return .diskImage }
        return .installed
    }

    public var shouldOfferMove: Bool { self != .installed }

    /// Where a moved Cellar goes: /Applications when this account may write there (an admin's),
    /// otherwise the account's own ~/Applications, which needs no password and still shows in
    /// Launchpad and Spotlight.
    public static func moveDestination(fileManager fm: FileManager = .default) -> URL {
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if fm.isWritableFile(atPath: system.path) {
            return system.appendingPathComponent("Cellar.app", isDirectory: true)
        }
        return fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Cellar.app", isDirectory: true)
    }
}
