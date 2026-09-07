import Foundation

/// Generates minimal double-clickable macOS .apps in ~/Applications whose launcher calls `cellar`:
/// one per game (`cellar launch <slug>`, also the Steam non-Steam-shortcut target) and one per
/// bottle for the Windows Steam client itself (`cellar steam open <slug>`).
public enum AppBundle {
    public struct Generated {
        public let app: URL
        public let launcher: URL   // Contents/MacOS/launcher — the Steam shortcut target
    }

    public static var applicationsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    }

    /// A game launcher: `<name>.app` → `cellar launch <slug>`.
    @discardableResult
    public static func generate(name: String, slug: String, cellarBinary: String) throws -> Generated {
        try generate(name: name, identifier: "it.clercq.cellar.\(slug)",
                     cellarBinary: cellarBinary, arguments: ["launch", slug],
                     icon: gameIcon(slug: slug))
    }

    /// The Windows Steam client of a bottle: `Steam (<Bottle>).app` → `cellar steam open <slug>`.
    /// Reuses the native Steam.app icon when it is installed, so it looks like Steam in Launchpad.
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

    /// The native macOS Steam client's icon, if Steam is installed.
    static func steamIcon() -> URL? {
        let candidates = [
            "/Applications/Steam.app/Contents/Resources/steam.icns",
            FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/Steam.app/Contents/Resources/steam.icns",
        ]
        return candidates.map { URL(fileURLWithPath: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// A user-supplied icon for a game: `<profiles>/<slug>.icns` next to the profile, if present.
    static func gameIcon(slug: String) -> URL? {
        for dir in Paths.profileSearchPaths {
            let icns = dir.appendingPathComponent("\(slug).icns")
            if FileManager.default.fileExists(atPath: icns.path) { return icns }
        }
        return nil
    }

    /// Best-effort absolute path to the running `cellar` binary (for the .app launcher script).
    public static func resolveCellarBinary() -> String {
        if let installed = Shell.which("cellar") { return installed }
        return ProcessInfo.processInfo.arguments.first.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        } ?? "/usr/local/bin/cellar"
    }
}
