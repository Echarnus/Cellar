import Foundation

public struct SteamShortcutEntry {
    public let appName: String
    public let exe: String           // path to the inner .app launcher, wrapped in literal quotes
    public let startDir: String      // its directory, wrapped in literal quotes
    public let icon: String
    public let launchOptions: String

    /// Build an entry that points Steam at a generated .app's inner launcher (so Steam tracks
    /// the process correctly for Play/Stop and current-session playtime).
    public init(appName: String, launcherBinary: URL, icon: String = "", launchOptions: String = "") {
        self.appName = appName
        self.exe = "\"\(launcherBinary.path)\""
        self.startDir = "\"\(launcherBinary.deletingLastPathComponent().path)/\""
        self.icon = icon
        self.launchOptions = launchOptions
    }
}

/// Reads/writes the native macOS Steam client's non-Steam-games file (shortcuts.vdf).
public enum SteamShortcuts {
    /// Steam's shortcut app id: CRC32(exe + appname) with the high bit set.
    public static func appID(exe: String, appName: String) -> UInt32 {
        CRC32.checksum(exe + appName) | 0x8000_0000
    }

    /// The active account's `config` directory (most-recently-modified userdata profile).
    public static func userdataConfigDir() -> URL? {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/userdata", isDirectory: true)
        guard let ids = try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }

        let candidates: [(URL, Date)] = ids.compactMap { dir in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let config = dir.appendingPathComponent("config", isDirectory: true)
            let date = (try? config.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return (config, date)
        }
        return candidates.sorted { $0.1 > $1.1 }.first?.0
    }

    /// Append a non-Steam shortcut. Parses the existing file (never blind byte-splicing),
    /// backs it up, and re-serializes. Steam must be fully quit first or it will clobber the file.
    @discardableResult
    public static func add(_ entry: SteamShortcutEntry, to configDir: URL) throws -> UInt32 {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let file = configDir.appendingPathComponent("shortcuts.vdf")

        var shortcuts: [(String, VDFValue)] = []
        if let data = try? Data(contentsOf: file), !data.isEmpty {
            if case .map(let root) = try BinaryVDF.parse(data),
               let node = root.first(where: { $0.0.lowercased() == "shortcuts" }),
               case .map(let existing) = node.1 {
                shortcuts = existing
            }
            try? data.write(to: configDir.appendingPathComponent("shortcuts.vdf.cellar.bak"))
        }

        let appid = appID(exe: entry.exe, appName: entry.appName)
        let entryMap: VDFValue = .map([
            ("appid", .uint32(appid)),
            ("appname", .string(entry.appName)),
            ("exe", .string(entry.exe)),
            ("StartDir", .string(entry.startDir)),
            ("icon", .string(entry.icon)),
            ("ShortcutPath", .string("")),
            ("LaunchOptions", .string(entry.launchOptions)),
            ("IsHidden", .uint32(0)),
            ("AllowDesktopConfig", .uint32(1)),
            ("AllowOverlay", .uint32(1)),
            ("OpenVR", .uint32(0)),
            ("Devkit", .uint32(0)),
            ("DevkitGameID", .string("")),
            ("LastPlayTime", .uint32(0)),
            ("tags", .map([])),
        ])
        shortcuts.append(("\(shortcuts.count)", entryMap))

        let out = BinaryVDF.serialize(.map([("shortcuts", .map(shortcuts))]))
        try out.write(to: file)
        return appid
    }

    /// Whether a shortcut Cellar added is in the file. Used to decide whether an uninstall has a
    /// Steam-library entry to clean up at all.
    ///
    /// `launcherPath` is what makes this **Cellar's** entry rather than one that merely shares a
    /// name: a player may well have added *Planet Coaster 2* to Steam by hand, and that shortcut is
    /// theirs. Same rule as the `.app` bundles — match on something we wrote, never on a name.
    public static func contains(appName: String, launcherPath: String? = nil, in configDir: URL) -> Bool {
        !matches(appName: appName, launcherPath: launcherPath, in: entriesWithExe(in: configDir)).isEmpty
    }

    /// Drop the shortcuts Cellar added under this name. Same discipline as `add`: parse, back up,
    /// re-serialize — never splice bytes — and renumber the remaining entries, because Steam reads
    /// the keys as a contiguous list and silently drops everything after a gap.
    ///
    /// Returns how many entries were removed.
    @discardableResult
    public static func remove(appName: String, launcherPath: String? = nil, from configDir: URL) throws -> Int {
        let file = configDir.appendingPathComponent("shortcuts.vdf")
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return 0 }
        guard case .map(let root) = try BinaryVDF.parse(data),
              let node = root.first(where: { $0.0.lowercased() == "shortcuts" }),
              case .map(let existing) = node.1 else { return 0 }

        let survivors = existing.filter { _, value in
            !isMatch(name: name(of: value), exe: exe(of: value), appName: appName, launcherPath: launcherPath)
        }
        guard survivors.count != existing.count else { return 0 }

        try? data.write(to: configDir.appendingPathComponent("shortcuts.vdf.cellar.bak"))
        let renumbered = survivors.enumerated().map { index, entry in ("\(index)", entry.1) }
        try BinaryVDF.serialize(.map([("shortcuts", .map(renumbered))])).write(to: file)
        return existing.count - survivors.count
    }

    /// The names of every shortcut whose target is a launcher Cellar generated.
    ///
    /// Matched on the **exe path**, never the name, so a player who added the same game to Steam by
    /// hand keeps their own entry. `directory` is normally `AppBundle.applicationsDirectory`; only
    /// entries pointing at a `.app/Contents/MacOS/launcher` inside it are ours.
    public static func cellarEntryNames(pointingInto directory: URL, in configDir: URL) -> [String] {
        let prefix = directory.standardizedFileURL.path
        return entriesWithExe(in: configDir).compactMap { entry in
            let exe = entry.exe.replacingOccurrences(of: "\"", with: "")
            guard exe.hasPrefix(prefix), exe.hasSuffix("/Contents/MacOS/launcher") else { return nil }
            return entry.name
        }
    }

    /// `(appname, exe)` for every shortcut in the file, or nothing when there is no file yet.
    static func entriesWithExe(in configDir: URL) -> [(name: String, exe: String)] {
        let file = configDir.appendingPathComponent("shortcuts.vdf")
        guard let data = try? Data(contentsOf: file), !data.isEmpty,
              case .map(let root)? = try? BinaryVDF.parse(data),
              let node = root.first(where: { $0.0.lowercased() == "shortcuts" }),
              case .map(let shortcuts) = node.1 else { return [] }
        return shortcuts.compactMap { _, value in
            guard let name = name(of: value) else { return nil }
            return (name, exe(of: value) ?? "")
        }
    }

    static func matches(appName: String, launcherPath: String?,
                        in entries: [(name: String, exe: String)]) -> [(name: String, exe: String)] {
        entries.filter { isMatch(name: $0.name, exe: $0.exe, appName: appName, launcherPath: launcherPath) }
    }

    /// A shortcut is Cellar's when the name matches *and* its target is the launcher Cellar
    /// generated. With no launcher path to check against, the name alone has to do.
    static func isMatch(name: String?, exe: String?, appName: String, launcherPath: String?) -> Bool {
        guard name == appName else { return false }
        guard let launcherPath else { return true }
        return (exe ?? "").contains(launcherPath)
    }

    static func name(of entry: VDFValue) -> String? { string("appname", of: entry) }
    static func exe(of entry: VDFValue) -> String? { string("exe", of: entry) }

    static func string(_ key: String, of entry: VDFValue) -> String? {
        guard case .map(let fields) = entry,
              let field = fields.first(where: { $0.0.lowercased() == key }),
              case .string(let value) = field.1 else { return nil }
        return value
    }

    public static var steamRunning: Bool {
        !Shell.run("/usr/bin/pgrep", ["-x", "steam_osx"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
