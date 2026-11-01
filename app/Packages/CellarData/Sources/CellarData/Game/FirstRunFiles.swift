import CellarDomain
import Foundation

/// Settings files a game's own launcher writes before the game first runs, and that the game
/// cannot start without (`first_run_files` in a profile).
///
/// Cellar starts a game's own exe, not the publisher's launcher in front of it, because that
/// launcher is a window with a Play button the player would have to press, inside a store client
/// that has already been told to play. Most launchers only pick a language or a server. Some also
/// write the game's settings on their first run, and the game then counts on those files: Skyrim
/// Special Edition's `SkyrimSELauncher.exe` copies `Skyrim_Default.ini` to
/// `My Games/Skyrim Special Edition/Skyrim.ini` and a quality preset to `SkyrimPrefs.ini`. With
/// neither there, `SkyrimSE.exe` made that folder and then crashed (0xC0000005), eight starts out of
/// eight, on Kenneth's Mac on 2026-11-01.
///
/// So a profile can name those copies, and Cellar makes them the way the launcher would: from the
/// game's own files, only where nothing exists yet. A file the game or the player already wrote is
/// never touched, so this runs before every launch and costs nothing after the first.
///
/// The value is `;`-separated `source > destination` pairs. The source is relative to the folder
/// that holds the profile's `exe`; the destination is relative to the Windows user folder, like
/// `save_paths`:
///
///     first_run_files = "Skyrim_Default.ini > Documents/My Games/Skyrim Special Edition/Skyrim.ini"
public enum FirstRunFiles {
    /// One copy to make.
    public struct Copy: Equatable, Sendable {
        /// Relative to the folder holding the game's exe.
        public var source: String
        /// Relative to the Windows user folder (`drive_c/users/<name>`).
        public var destination: String
    }

    /// `"A.ini > Documents/X/A.ini; B.ini > Documents/X/B.ini"` → two copies. A pair without a `>`,
    /// with an empty side, or that climbs out of its folder with `..` is dropped.
    public static func parse(_ value: String?) -> [Copy] {
        guard let value else { return [] }
        return value.split(separator: ";").compactMap { pair in
            let sides = pair.split(separator: ">", maxSplits: 1).map { clean(String($0)) }
            guard sides.count == 2, let source = sides[0], let destination = sides[1] else { return nil }
            return Copy(source: source, destination: destination)
        }
    }

    /// A relative path with Windows separators turned into `/`, or nil when it is empty or uses `..`.
    private static func clean(_ path: String) -> String? {
        let path = path.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty, !path.split(separator: "/").contains("..") else { return nil }
        return path
    }

    /// Make the plan's copies that are still missing. Returns the files written.
    ///
    /// - Parameters:
    ///   - gameFolder: the folder holding the game's exe.
    ///   - userFolder: the bottle's Windows user folder. Its `Documents` is usually a link to the
    ///     Mac's own, and the copy follows it there, because that is where the game will look.
    @discardableResult
    public static func seed(_ copies: [Copy], gameFolder: URL, userFolder: URL) -> [URL] {
        let fm = FileManager.default
        guard !copies.isEmpty, fm.fileExists(atPath: userFolder.path) else { return [] }
        var written: [URL] = []
        for copy in copies {
            let source = gameFolder.appendingPathComponent(copy.source)
            let destination = userFolder.appendingPathComponent(copy.destination)
            // `fileExists` follows links, so a settings file the player keeps elsewhere counts.
            guard !fm.fileExists(atPath: destination.path) else { continue }
            guard fm.fileExists(atPath: source.path) else {
                CellarLog.warn(.launch, "Can't write \(copy.destination) before the first start: "
                    + "the game has no \(copy.source).")
                continue
            }
            do {
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: destination)
                written.append(destination)
            } catch {
                CellarLog.warn(.launch, "Couldn't write \(copy.destination) before the first start: "
                    + CellarLog.describe(error))
            }
        }
        return written
    }

    /// Make a game's first-run files before it starts. Nothing to do for a profile without any, or
    /// a game whose exe isn't on disk yet.
    @discardableResult
    public static func seed(_ plan: GamePlan, progress: (String) -> Void = { _ in }) -> [URL] {
        guard !plan.firstRunFiles.isEmpty, let exe = plan.directLaunchExe else { return [] }
        let written = seed(plan.firstRunFiles, gameFolder: exe.deletingLastPathComponent(),
                           userFolder: userFolder(of: plan))
        if !written.isEmpty {
            let names = written.map(\.lastPathComponent).joined(separator: " and ")
            progress("Setting up \(plan.name)'s settings for its first start (\(names))…")
            CellarLog.info(.launch, "Wrote \(plan.name)'s first-run settings: "
                + written.map(\.path).joined(separator: ", "), subject: plan.slug)
        }
        return written
    }

    /// The bottle's Windows user folder: Wine names it after the Mac user it runs as.
    static func userFolder(of plan: GamePlan) -> URL {
        plan.prefix.appendingPathComponent("drive_c/users", isDirectory: true)
            .appendingPathComponent(SteamClientSession.wineUser(environment: ProcessInfo.processInfo.environment),
                                    isDirectory: true)
    }
}
