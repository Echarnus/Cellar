import Foundation

/// Copies of one bottle's save games, taken before anything that could lose them and on request.
///
/// A save lives inside the bottle (`drive_c/users/<name>/…`), so resetting a bottle, removing it, or
/// a runner or game update that goes wrong takes with it every save the game never synced to a
/// cloud. So Cellar copies them out first, automatically, and keeps the last few — and a player can
/// put any of them back.
///
/// The copies live under `Paths.saveBackups`, beside the bottles rather than inside them, so the
/// very removal they protect against cannot take them too. `cellar reset` leaves them alone.
///
/// Which folders count: a profile can name them (`save_paths`, relative to the Windows user folder,
/// `;`-separated). Without that, it is every folder `SaveGames` would call a save in this bottle —
/// generous, because copying a cache too costs some disk, and missing a save costs the save.
public enum SaveBackups {

    /// Why a backup was taken — said back to the player when they choose which one to restore.
    public enum Reason: String, Codable, Sendable, CaseIterable {
        case manual
        case beforeReset = "before-reset"
        case beforeRemoval = "before-removal"
        case beforeGameUpdate = "before-game-update"
        case beforeRunnerUpdate = "before-runner-update"
        case beforeRestore = "before-restore"

        public var description: String {
            switch self {
            case .manual:             return "Backed up by you"
            case .beforeReset:        return "Before a reset"
            case .beforeRemoval:      return "Before the bottle was removed"
            case .beforeGameUpdate:   return "Before a game update"
            case .beforeRunnerUpdate: return "Before a runner update"
            case .beforeRestore:      return "Before restoring an older backup"
            }
        }
    }

    /// What a backup holds, written beside the files as `backup.json`.
    public struct Manifest: Codable, Sendable {
        public let created: Date
        public let reason: Reason
        /// The folders copied, relative to `drive_c/users` — where each one goes back to.
        public let paths: [String]
        public let bytes: Int64
    }

    /// One backup on disk.
    public struct Backup: Sendable {
        public let url: URL
        public let manifest: Manifest
        /// The folder name, which is also how the CLI names it: `2026-10-30 22.41.07`.
        public var id: String { url.lastPathComponent }
        var files: URL { url.appendingPathComponent("files", isDirectory: true) }
    }

    /// How many backups a bottle keeps. Older ones go as new ones arrive.
    public static let keep = 10

    static let manifestName = "backup.json"

    /// Where one bottle's backups live.
    public static func directory(forBottle name: String) -> URL {
        Paths.saveBackups.appendingPathComponent(name, isDirectory: true)
    }

    // MARK: - What to copy

    /// The save folders a bottle's profiles name, or nil when any game in it doesn't name its own —
    /// a bottle shared with a game whose saves are unknown is backed up the generous way.
    public static func declaredPaths(forBottle name: String) -> [String]? {
        var paths: [String] = []
        for slug in Game.slugs(sharingBottle: name) {
            guard let ref = ProfileStore.find(slug), let value = ProfileStore.fields(ref)["save_paths"] else {
                return nil
            }
            paths += parse(value)
        }
        return paths.isEmpty ? nil : paths
    }

    /// `"Documents\My Games\X; Saved Games/X"` → `["Documents/My Games/X", "Saved Games/X"]`.
    static func parse(_ value: String) -> [String] {
        value.split(separator: ";").map {
            $0.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }.filter { !$0.isEmpty && !$0.split(separator: "/").contains("..") }
    }

    /// The folders that would be copied now, relative to `drive_c/users`, with where they are.
    public static func locations(inBottle bottle: URL, declared: [String]?) -> [(relativePath: String, url: URL)] {
        guard let declared else {
            return SaveGames.locate(inBottle: bottle).map { ($0.relativePath, $0.url) }
        }
        let fm = FileManager.default
        let users = bottle.appendingPathComponent("drive_c/users", isDirectory: true)
        let profiles = (try? fm.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? []
        var found: [(relativePath: String, url: URL)] = []
        for profile in profiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where SaveGames.isDirectory(profile) && !SaveGames.isLink(profile) {
            for path in declared {
                let url = profile.appendingPathComponent(path)
                // A folder reached through a link is the Mac's own (Documents, when Cellar was
                // allowed to link it): not at risk, and not Cellar's to overwrite on a restore.
                guard fm.fileExists(atPath: url.path), !crossesLink(from: profile, path: path) else { continue }
                found.append(("\(profile.lastPathComponent)/\(path)", url))
            }
        }
        return found
    }

    static func crossesLink(from base: URL, path: String) -> Bool {
        var url = base
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
            if SaveGames.isLink(url) { return true }
        }
        return false
    }

    // MARK: - Taking one

    /// Copy the bottle's saves out. Nil when there is nothing to copy — no bottle, or no saves yet.
    /// Throws on the first failure and leaves no half-written backup behind, so a caller about to
    /// delete something can stop instead.
    @discardableResult
    public static func backUp(bottle: URL, reason: Reason, now: Date = Date(), prune: Bool = true) throws -> Backup? {
        let name = bottle.lastPathComponent
        let found = locations(inBottle: bottle, declared: declaredPaths(forBottle: name))
        guard !found.isEmpty else { return nil }

        let fm = FileManager.default
        let target = uniqueFolder(in: directory(forBottle: name), for: now)
        let files = target.appendingPathComponent("files", isDirectory: true)
        do {
            var bytes: Int64 = 0
            for location in found {
                let copy = files.appendingPathComponent(location.relativePath)
                try fm.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: location.url, to: copy)
                bytes += Reset.size(of: copy)
            }
            let manifest = Manifest(created: now, reason: reason, paths: found.map(\.relativePath), bytes: bytes)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: target.appendingPathComponent(manifestName))
            CellarLog.info(.prefix, "Backed up \(found.count) save folder(s), \(ByteSize.describe(bytes)) — "
                + reason.description.lowercased() + ".", subject: name)
            if prune { self.prune(bottle: name) }
            return Backup(url: target, manifest: manifest)
        } catch {
            try? fm.removeItem(at: target)
            throw error
        }
    }

    /// Back up every bottle, for a reset that removes them all. Returns the bottles that failed.
    public static func backUpAllBottles(reason: Reason, progress: (String) -> Void = { _ in }) -> [String] {
        let fm = FileManager.default
        let bottles = (try? fm.contentsOfDirectory(at: Paths.prefixes, includingPropertiesForKeys: nil)) ?? []
        var failed: [String] = []
        for bottle in bottles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where bottle.lastPathComponent != Preparation.scaffoldBottle && SaveGames.isDirectory(bottle) {
            do {
                if try backUp(bottle: bottle, reason: reason) != nil {
                    progress("Backed up the save games in '\(bottle.lastPathComponent)'.")
                }
            } catch {
                CellarLog.failure(.prefix, "Couldn't back up the saves in '\(bottle.lastPathComponent)'", error,
                                  subject: bottle.lastPathComponent)
                failed.append(bottle.lastPathComponent)
            }
        }
        return failed
    }

    /// A best-effort backup before something that should not lose saves but is not deleting them
    /// either — an update. Logged, never thrown: refusing to update a game over a backup is worse.
    public static func backUpQuietly(bottle: URL, reason: Reason) {
        do { try backUp(bottle: bottle, reason: reason) } catch {
            CellarLog.failure(.prefix, "Couldn't back up the saves first", error, subject: bottle.lastPathComponent)
        }
    }

    // MARK: - Reading them back

    /// A bottle's backups, newest first. Folders without a readable manifest are not backups.
    public static func list(bottle name: String) -> [Backup] {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: directory(forBottle: name), includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return folders.compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent(manifestName)),
                  let manifest = try? decoder.decode(Manifest.self, from: data) else { return nil }
            return Backup(url: url, manifest: manifest)
        }.sorted { ($0.manifest.created, $0.id) > ($1.manifest.created, $1.id) }
    }

    /// Put a backup's folders back where they came from. The bottle's current saves are backed up
    /// first, so a restore is itself undoable. Folders the backup doesn't hold are left alone.
    public static func restore(_ backup: Backup, into bottle: URL, progress: (String) -> Void = { _ in }) throws {
        let fm = FileManager.default
        let users = bottle.appendingPathComponent("drive_c/users", isDirectory: true)
        guard SaveGames.isDirectory(users) else {
            throw CellarError.invalidArgument("The bottle '\(bottle.lastPathComponent)' has no Windows user folder yet. Set the game up first.")
        }
        // Not pruned until the restore is done: the backup being restored may be the oldest one.
        if try backUp(bottle: bottle, reason: .beforeRestore, prune: false) != nil {
            progress("Kept a copy of the saves as they are now, in case you want them back.")
        }
        for path in backup.manifest.paths {
            let source = backup.files.appendingPathComponent(path)
            guard fm.fileExists(atPath: source.path) else { continue }
            let parts = path.split(separator: "/")
            guard parts.count > 1, !parts.contains(".."), !crossesLink(from: users, path: path) else { continue }
            let target = users.appendingPathComponent(path)
            progress("Restoring \(path)…")
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: source, to: target)
        }
        CellarLog.info(.prefix, "Restored the save games from \(backup.id).", subject: bottle.lastPathComponent)
        prune(bottle: bottle.lastPathComponent, sparing: backup.id)
    }

    /// Keep the newest `keep` backups. `sparing` survives even when it is older.
    static func prune(bottle name: String, sparing: String? = nil) {
        for old in list(bottle: name).dropFirst(keep) where old.id != sparing {
            try? FileManager.default.removeItem(at: old.url)
        }
    }

    /// A dated folder that doesn't exist yet — two backups in one second get `-2`, `-3`.
    static func uniqueFolder(in parent: URL, for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stem = formatter.string(from: date)
        var candidate = parent.appendingPathComponent(stem, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(stem)-\(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }
}
