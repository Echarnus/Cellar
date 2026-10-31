import CellarDomain
import Foundation

/// Where Cellar's disk space goes, what can safely be given back, and games moved to another drive.
///
/// A modern game is 50 to 150 GB and a Mac's internal SSD is the most expensive storage it has. So
/// a game Cellar installed itself (a Steam depot download, a GOG install — both under the bottle's
/// `C:\Games`) can live on an external drive: its folder is copied to `<drive>/Cellar Games/<slug>`
/// and the bottle keeps a link to it, so Wine, updates and uninstall find it where they always did.
///
/// A drive that isn't connected is said as that, by name, before anything tries to launch or
/// download into the dangling link — never as "not installed", which would invite a re-download
/// onto the internal disk the player was trying to keep free.
public enum GameStorage {

    // MARK: - What uses the space

    public struct Usage: Sendable {
        public let label: String
        public let url: URL
        public let bytes: Int64
        /// Safe to delete: Cellar re-creates it when needed and nothing the player made is in it.
        public let cleanable: Bool
    }

    /// Everything Cellar keeps, largest first: each game's files, then the shared parts.
    public static func usage() -> [Usage] {
        var items: [Usage] = []
        for ref in ProfileStore.all() {
            guard let plan = try? Game.plan(slug: ref.slug), let root = Uninstall.installedRoot(plan) else { continue }
            let where_ = movedLocation(slug: plan.slug) == nil ? "" : " (on \(volumeName(of: root)))"
            items.append(Usage(label: plan.name + where_, url: root, bytes: ByteSize.of(root), cleanable: false))
        }
        func add(_ label: String, _ url: URL, cleanable: Bool = false) {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            items.append(Usage(label: label, url: url, bytes: ByteSize.of(url), cleanable: cleanable))
        }
        add("Windows Steam (shared by every Steam game)", Paths.sharedSteam)
        add("Wine runners", Paths.runners)
        add("Save game backups", Paths.saveBackups)
        add("Downloaded installers and scratch files", Paths.cache, cleanable: true)
        return items.sorted { $0.bytes > $1.bytes }
    }

    /// Empty the cache. Returns the bytes given back. Skips anything a download is writing into.
    @discardableResult
    public static func clean(progress: (String) -> Void = { _ in }) -> Int64 {
        let fm = FileManager.default
        var freed: Int64 = 0
        for entry in (try? fm.contentsOfDirectory(at: Paths.cache, includingPropertiesForKeys: nil)) ?? [] {
            // Icons are what the library and the launcher apps draw; they are small and re-made
            // slowly, so they stay.
            guard entry.lastPathComponent != "icons" else { continue }
            let bytes = ByteSize.of(entry)
            do {
                try fm.removeItem(at: entry)
                freed += bytes
                progress("Removed \(entry.lastPathComponent) (\(ByteSize.describe(bytes)))")
            } catch {
                progress("Kept \(entry.lastPathComponent): \(CellarLog.describe(error))")
            }
        }
        return freed
    }

    // MARK: - Moving a game

    /// The folder on another drive a game lives in, if it was moved.
    public static func movedLocation(slug: String) -> URL? {
        moved()[slug].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// The name of the drive a moved game is on, when that drive isn't connected now.
    public static func missingDrive(_ plan: GamePlan) -> String? {
        guard let location = movedLocation(slug: plan.slug),
              !FileManager.default.fileExists(atPath: location.path) else { return nil }
        return volumeName(of: location)
    }

    /// The error every path that needs a moved game's files throws when its drive is gone.
    public static func missingDriveError(_ plan: GamePlan) -> CellarError? {
        missingDrive(plan).map {
            CellarError.ioFailure("\(plan.name) is on the drive “\($0)”, which isn't connected. Connect it, then try again.")
        }
    }

    /// The game's folder in the bottle, when Cellar installed it and it can be moved: Cellar's own
    /// `C:\Games` folder, not a client's library — Steam keeps its own list of where games are.
    public static func movableFolder(_ plan: GamePlan) -> URL? {
        if movedLocation(slug: plan.slug) != nil { return linkInBottle(plan) }
        guard let root = Uninstall.installedRoot(plan) else { return nil }
        let games = plan.prefix.appendingPathComponent("drive_c/Games", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL.path
        guard root.deletingLastPathComponent().standardizedFileURL.path == games else { return nil }
        return root
    }

    /// Move a game's files to `<destination>/Cellar Games/<slug>` and leave a link in the bottle.
    /// Copied first and removed after, so an unplugged drive mid-copy leaves the game where it was.
    public static func move(_ plan: GamePlan, to destination: URL, progress: (String) -> Void = { _ in }) throws {
        if let error = missingDriveError(plan) { throw error }
        guard let folder = movableFolder(plan) else {
            throw CellarError.invalidArgument(plan.store == .steam
                ? "\(plan.name) was installed by the Steam client, which keeps its own list of where games are. Only games Cellar downloaded itself can be moved."
                : "\(plan.name) isn't installed in a folder Cellar can move.")
        }
        guard !Uninstall.isGameRunning(plan) else {
            throw CellarError.invalidArgument("\(plan.name) is running. Quit it, then move it.")
        }
        let fm = FileManager.default
        let target = destination.appendingPathComponent("Cellar Games", isDirectory: true)
            .appendingPathComponent(plan.slug, isDirectory: true)
        guard !fm.fileExists(atPath: target.path) else {
            throw CellarError.invalidArgument("There is already a folder at \(target.path). Move or rename it first.")
        }
        let source = folder.resolvingSymlinksInPath()
        let bytes = ByteSize.of(source)
        if let free = try? destination.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, free < bytes {
            throw CellarError.invalidArgument(
                "\(volumeName(of: destination)) has \(ByteSize.describe(free)) free; \(plan.name) needs \(ByteSize.describe(bytes)).")
        }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        progress("Copying \(plan.name) (\(ByteSize.describe(bytes))) to \(volumeName(of: destination))…")
        do {
            try fm.copyItem(at: source, to: target)
        } catch {
            try? fm.removeItem(at: target)
            throw error
        }
        progress("Copied. Removing the copy on this Mac…")
        try fm.removeItem(at: folder)                     // a link from an earlier move, or the folder itself
        if source != folder.standardizedFileURL, Uninstall.isDeletable(source) { try? fm.removeItem(at: source) }
        try fm.createSymbolicLink(at: folder, withDestinationURL: target)
        record(slug: plan.slug, location: target)
        CellarLog.info(.install, "Moved \(plan.name) to \(Diagnostics.redact(target.path)).", subject: plan.slug)
    }

    /// Bring a moved game back into its bottle.
    public static func moveBack(_ plan: GamePlan, progress: (String) -> Void = { _ in }) throws {
        guard let location = movedLocation(slug: plan.slug) else {
            throw CellarError.invalidArgument("\(plan.name) is already on this Mac.")
        }
        if let error = missingDriveError(plan) { throw error }
        guard let folder = movableFolder(plan) else {
            throw CellarError.invalidArgument("Cellar can't find \(plan.name)'s folder in its bottle.")
        }
        guard !Uninstall.isGameRunning(plan) else {
            throw CellarError.invalidArgument("\(plan.name) is running. Quit it, then move it.")
        }
        let fm = FileManager.default
        let staging = folder.deletingLastPathComponent().appendingPathComponent(".\(folder.lastPathComponent)-incoming")
        try? fm.removeItem(at: staging)
        progress("Copying \(plan.name) back to this Mac (\(ByteSize.describe(ByteSize.of(location))))…")
        do { try fm.copyItem(at: location, to: staging) } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
        try fm.removeItem(at: folder)                     // the link
        try fm.moveItem(at: staging, to: folder)
        try? fm.removeItem(at: location)
        record(slug: plan.slug, location: nil)
        progress("\(plan.name) is back on this Mac.")
    }

    /// The bottle's link for a moved game whose installed root can't be read (its exe moved).
    static func linkInBottle(_ plan: GamePlan) -> URL? {
        let games = plan.prefix.appendingPathComponent("drive_c/Games", isDirectory: true)
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(at: games, includingPropertiesForKeys: nil)) ?? []).first { url in
            Uninstall.isSymbolicLink(url) && (try? fm.destinationOfSymbolicLink(atPath: url.path))
                .map { URL(fileURLWithPath: $0).standardizedFileURL == movedLocation(slug: plan.slug)?.standardizedFileURL } == true
        }
    }

    /// The `Cellar Games` folders games were moved into — Cellar's to delete inside, like its own.
    static var movedRoots: [URL] {
        Set(moved().values.map { URL(fileURLWithPath: $0).deletingLastPathComponent().standardizedFileURL.path })
            .sorted().map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func volumeName(of url: URL) -> String {
        let components = url.standardizedFileURL.pathComponents
        if components.count > 2, components[1] == "Volumes" { return components[2] }
        return (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "this Mac"
    }

    // MARK: - The record

    static var recordFile: URL { Paths.appSupport.appendingPathComponent("moved-games.json") }

    static func moved() -> [String: String] {
        guard let data = try? Data(contentsOf: recordFile),
              let all = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return all
    }

    static func record(slug: String, location: URL?) {
        var all = moved()
        all[slug] = location?.standardizedFileURL.path
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? data.write(to: recordFile, options: .atomic)
    }
}
