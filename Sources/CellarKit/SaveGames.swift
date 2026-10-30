import Foundation

/// The save games inside Cellar's bottles, found and copied out before an uninstall removes them.
///
/// A Windows game saves into its user folders — Documents\My Games, Saved Games, AppData — and in
/// a bottle those live under `drive_c/users/<name>`. Wiping bottles therefore wipes every save a
/// game never synced to a cloud, which is the one thing an uninstall must not do by surprise. So
/// "keep my save games" is a real option, and the default: copy them out first, delete after.
///
/// Where Cellar was allowed to, a bottle's Documents is a link to the Mac's own Documents folder
/// (`HomeFolderAccess`). Those saves already live outside Cellar and an uninstall never touches
/// them, so a link is noted rather than followed and copied.
public enum SaveGames {

    /// One folder of saves, in one bottle.
    public struct Location: Sendable {
        public let bottle: String
        /// Where it is now.
        public let url: URL
        /// Where it goes under the bottle's folder in the copy: `Saved Games`, `AppData/Roaming/…`.
        public let relativePath: String
        public let bytes: Int64
    }

    /// The Windows user folders games write saves into, relative to a user's profile directory.
    static let saveFolders = ["Documents", "Saved Games", "AppData/Roaming", "AppData/LocalLow", "AppData/Local"]

    /// Folders Wine, Windows or a store client keep in AppData that are not anyone's save game:
    /// caches, temp files, and the clients' own state, which can run to gigabytes.
    static let notSaves: Set<String> = [
        "temp", "microsoft", "steam", "battle.net", "blizzard entertainment", "gog.com",
        "galaxy", "crashdumps", "d3dscache", "nvidia", "cache", "caches", "webcache",
    ]

    /// Every folder of saves in every bottle, plus the Steam client's own `userdata` — where a
    /// game using Steam's storage keeps its local copy. Sizes measured; empty folders left out.
    public static func locate() -> [Location] {
        let fm = FileManager.default
        var found: [Location] = []
        let bottles = (try? fm.contentsOfDirectory(at: Paths.prefixes, includingPropertiesForKeys: nil)) ?? []
        for bottle in bottles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where bottle.lastPathComponent != Preparation.scaffoldBottle && isDirectory(bottle) {
            found += locate(inBottle: bottle)
        }
        let userdata = Paths.sharedSteam.appendingPathComponent("userdata", isDirectory: true)
        if isDirectory(userdata), !isLink(userdata) {
            let bytes = Reset.size(of: userdata)
            if bytes > 0 {
                found.append(Location(bottle: "Steam", url: userdata, relativePath: "userdata", bytes: bytes))
            }
        }
        return found
    }

    /// The folders of saves in one bottle, by the same rules as `locate()`: the Windows user folders
    /// games write into, minus links (the Mac's own folders) and the clients' caches.
    public static func locate(inBottle bottle: URL) -> [Location] {
        let fm = FileManager.default
        var found: [Location] = []
        let users = bottle.appendingPathComponent("drive_c/users", isDirectory: true)
        let profiles = (try? fm.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? []
        for profile in profiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where isDirectory(profile) && !isLink(profile) {
            for folder in saveFolders {
                let url = profile.appendingPathComponent(folder, isDirectory: true)
                // A link is the Mac's real folder: it is not Cellar's, and it is not deleted.
                guard isDirectory(url), !isLink(url) else { continue }
                let entries = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where !isLink(entry) {
                    let name = entry.lastPathComponent
                    if folder.hasPrefix("AppData"), notSaves.contains(name.lowercased()) { continue }
                    let bytes = Reset.size(of: entry)
                    guard bytes > 0 else { continue }
                    found.append(Location(
                        bottle: bottle.lastPathComponent, url: entry,
                        relativePath: "\(profile.lastPathComponent)/\(folder)/\(name)", bytes: bytes))
                }
            }
        }
        return found
    }

    /// Whether any bottle's Documents is a link to the Mac's own Documents, so the summary can say
    /// those saves stay where they are rather than leaving the player to wonder.
    public static var someSavesAlreadyInDocuments: Bool {
        let fm = FileManager.default
        let bottles = (try? fm.contentsOfDirectory(at: Paths.prefixes, includingPropertiesForKeys: nil)) ?? []
        return bottles.contains { bottle in
            let users = bottle.appendingPathComponent("drive_c/users", isDirectory: true)
            let profiles = (try? fm.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? []
            return profiles.contains { isLink($0.appendingPathComponent("Documents")) }
        }
    }

    /// `~/Documents/Cellar Saved Games/<date and time>` — dated, so a second uninstall (or a second
    /// Mac's) never lands on top of the first.
    public static func defaultDestination(now: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Cellar Saved Games", isDirectory: true)
            .appendingPathComponent(formatter.string(from: now), isDirectory: true)
    }

    /// Copy every location into `destination/<bottle>/<relative path>`, with a note saying where
    /// each one came from. Throws on the first failure, so the caller can stop before it deletes
    /// anything: a copy that half worked is not a reason to remove the originals.
    @discardableResult
    public static func export(_ locations: [Location], to destination: URL,
                              progress: (String) -> Void = { _ in }) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for location in locations {
            let target = destination.appendingPathComponent(location.bottle, isDirectory: true)
                .appendingPathComponent(location.relativePath)
            progress("Copying \(location.bottle) › \(location.relativePath)…")
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: location.url, to: target)
        }
        let note = """
        Save games copied out of Cellar before it was uninstalled.

        Each folder is named after the bottle (one per game) it came from, and inside it the path
        is the one the game used under C:\\users\\<name>\\ — Documents, Saved Games or AppData.
        "Steam/userdata" is the Windows Steam client's local copy of games' Steam Cloud data.

        To use one again after reinstalling Cellar and setting the game up, copy its folder back
        into ~/Library/Application Support/Cellar/prefixes/<bottle>/drive_c/users/ — or, for a
        game that keeps its saves in Steam Cloud, just play: Steam brings them back itself.
        """
        try note.write(to: destination.appendingPathComponent("About these files.txt"),
                       atomically: true, encoding: .utf8)
        return destination
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func isLink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }
}
