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

    public static var steamRunning: Bool {
        !Shell.run("/usr/bin/pgrep", ["-x", "steam_osx"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
