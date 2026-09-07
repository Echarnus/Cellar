import Foundation

/// Generates minimal double-clickable macOS .apps in ~/Applications whose launcher calls `cellar`:
/// one per game (`cellar launch <slug>`, also the Steam non-Steam-shortcut target) and one per
/// bottle for the Windows Steam client itself (`cellar steam open <slug>`). Game launchers get the
/// game's own icon, extracted from the bottle and converted to `.icns`.
public enum AppBundle {
    public struct Generated {
        public let app: URL
        public let launcher: URL   // Contents/MacOS/launcher — the Steam shortcut target
    }

    public static var applicationsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    }

    /// A game launcher: `<name>.app` → `cellar launch <slug>`. Uses the game's own icon when the
    /// bottle is known (so the app shows the game's artwork in Launchpad/Finder, not a blank tile).
    @discardableResult
    public static func generate(name: String, slug: String, cellarBinary: String,
                                prefix: URL? = nil, appID: Int? = nil) throws -> Generated {
        try generate(name: name, identifier: "it.clercq.cellar.\(slug)",
                     cellarBinary: cellarBinary, arguments: ["launch", slug],
                     icon: resolveGameICNS(slug: slug, prefix: prefix, appID: appID))
    }

    /// The Windows Steam client of a bottle: `Steam (<Bottle>).app` → `cellar steam open <slug>`.
    /// Reuses the native Steam.app icon when installed, so it looks like Steam in Launchpad.
    @discardableResult
    public static func generateSteamClient(bottle: String, slug: String, cellarBinary: String) throws -> Generated {
        try generate(name: "Steam (\(bottle))", identifier: "it.clercq.cellar.steam.\(bottle)",
                     cellarBinary: cellarBinary, arguments: ["steam", "open", slug],
                     icon: steamIcon())
    }

    static func generate(name: String, identifier: String, cellarBinary: String,
                         arguments: [String], icon: URL?) throws -> Generated {
        let fm = FileManager.default
        let apps = applicationsDirectory
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)

        let app = apps.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        // Launcher script — double-clicked apps don't inherit the shell PATH, so use an absolute cellar path.
        let launcher = macOS.appendingPathComponent("launcher")
        let quoted = arguments.map { "'\($0)'" }.joined(separator: " ")
        let script = """
        #!/bin/sh
        exec "\(cellarBinary)" \(quoted)
        """
        try script.write(to: launcher, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        var iconEntry = ""
        if let icon, fm.fileExists(atPath: icon.path) {
            let dest = resources.appendingPathComponent("app.icns")
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: icon, to: dest)
            iconEntry = "<key>CFBundleIconFile</key><string>app</string>\n"
        }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key><string>launcher</string>
            <key>CFBundleIdentifier</key><string>\(identifier)</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>CFBundleName</key><string>\(name)</string>
            <key>CFBundleDisplayName</key><string>\(name)</string>
            <key>CFBundleShortVersionString</key><string>1.0</string>
            <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
            <key>LSMinimumSystemVersion</key><string>14.0</string>
            \(iconEntry)
        </dict>
        </plist>
        """
        try plist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        // Locally-generated unsigned bundle: clear quarantine and register with LaunchServices.
        Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        if fm.fileExists(atPath: lsregister) {
            Shell.run(lsregister, ["-f", app.path])
        }
        // Finder caches icons per bundle path; touching the bundle makes it re-read Info.plist.
        Shell.run("/usr/bin/touch", [app.path])

        return Generated(app: app, launcher: launcher)
    }

    // MARK: - Icons

    /// The native macOS Steam client's icon, if Steam is installed. (Its file is `Steam.icns` — the
    /// capital matters on a case-sensitive volume.)
    static func steamIcon() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/Applications/Steam.app/Contents/Resources/Steam.icns",
            "\(home)/Applications/Steam.app/Contents/Resources/Steam.icns",
        ]
        return candidates.map { URL(fileURLWithPath: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Resolve an `.icns` for a game launcher, in order: a user-supplied icon next to the profile,
    /// a previously-extracted cached icon, or a fresh extraction of the game's own icon from the
    /// bottle (converted from its Windows `.ico`). Returns nil if none can be produced.
    static func resolveGameICNS(slug: String, prefix: URL?, appID: Int?) -> URL? {
        let fm = FileManager.default
        // 1. user-supplied <profiles>/<slug>.icns
        for dir in Paths.profileSearchPaths {
            let icns = dir.appendingPathComponent("\(slug).icns")
            if fm.fileExists(atPath: icns.path) { return icns }
        }
        // 2. cached extraction
        let cached = Paths.cache.appendingPathComponent("icons/\(slug).icns")
        if fm.fileExists(atPath: cached.path) { return cached }
        // 3. extract from the bottle
        guard let prefix, let ico = findGameICO(prefix: prefix, appID: appID) else { return nil }
        try? fm.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
        return convertICOtoICNS(ico, to: cached) ? cached : nil
    }

    /// Locate a Windows `.ico` for the game inside the bottle: the game's own `game.ico` in its
    /// install directory (from the appmanifest), else the largest desktop-shortcut icon Steam keeps
    /// in `steam/games` (skipping Steam's own built-ins).
    static func findGameICO(prefix: URL, appID: Int?) -> URL? {
        let fm = FileManager.default
        let steam = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam")

        if let appID,
           let manifest = try? String(contentsOf: steam.appendingPathComponent("steamapps/appmanifest_\(appID).acf"), encoding: .utf8),
           let m = manifest.range(of: #""installdir"\s*"([^"]+)""#, options: .regularExpression) {
            let installdir = String(manifest[m]).components(separatedBy: "\"").dropLast().last ?? ""
            for name in ["game.ico", "\(installdir).ico"] {
                let ico = steam.appendingPathComponent("steamapps/common/\(installdir)/\(name)")
                if fm.fileExists(atPath: ico.path) { return ico }
            }
        }

        let gamesDir = steam.appendingPathComponent("steam/games")
        if let entries = try? fm.contentsOfDirectory(at: gamesDir, includingPropertiesForKeys: [.fileSizeKey]) {
            let icos = entries.filter { $0.pathExtension.lowercased() == "ico"
                && !["SteamMovie.ico", "PlatformMenu.ico"].contains($0.lastPathComponent) }
            return icos.max { a, b in
                let sa = (try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let sb = (try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return sa < sb
            }
        }
        return nil
    }

    /// Convert a Windows `.ico` to a multi-resolution macOS `.icns` via sips + iconutil.
    @discardableResult
    static func convertICOtoICNS(_ ico: URL, to icns: URL) -> Bool {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-icon-\(UUID().uuidString)")
        let png = tmp.appendingPathExtension("png")
        let iconset = tmp.appendingPathExtension("iconset")
        defer { try? FileManager.default.removeItem(at: png); try? FileManager.default.removeItem(at: iconset) }

        // Flatten the .ico to its largest PNG.
        guard Shell.run("/usr/bin/sips", ["-s", "format", "png", ico.path, "--out", png.path]).succeeded else { return false }
        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for (suffix, px) in [("", size), ("@2x", size * 2)] {
                let name = "icon_\(size)x\(size)\(suffix).png"
                Shell.run("/usr/bin/sips", ["-z", "\(px)", "\(px)", png.path,
                                            "--out", iconset.appendingPathComponent(name).path])
            }
        }
        try? FileManager.default.removeItem(at: icns)
        return Shell.run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", icns.path]).succeeded
            && FileManager.default.fileExists(atPath: icns.path)
    }

    /// Best-effort absolute path to the running `cellar` binary (for the .app launcher script).
    public static func resolveCellarBinary() -> String {
        if let installed = Shell.which("cellar") { return installed }
        return ProcessInfo.processInfo.arguments.first.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        } ?? "/usr/local/bin/cellar"
    }
}
