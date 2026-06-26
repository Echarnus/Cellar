import Foundation

/// Generates a minimal double-clickable macOS .app whose launcher calls `cellar launch <slug>`.
/// The same .app is used as the Steam non-Steam-shortcut target.
public enum AppBundle {
    public struct Generated {
        public let app: URL
        public let launcher: URL   // Contents/MacOS/launcher — the Steam shortcut target
    }

    @discardableResult
    public static func generate(name: String, slug: String, cellarBinary: String) throws -> Generated {
        let apps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)

        let app = apps.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)

        // Launcher script — double-clicked apps don't inherit the shell PATH, so use an absolute cellar path.
        let launcher = macOS.appendingPathComponent("launcher")
        let script = """
        #!/bin/sh
        exec "\(cellarBinary)" launch \(slug)
        """
        try script.write(to: launcher, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key><string>launcher</string>
            <key>CFBundleIdentifier</key><string>it.clercq.cellar.\(slug)</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>CFBundleName</key><string>\(name)</string>
            <key>CFBundleShortVersionString</key><string>1.0</string>
            <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
            <key>LSMinimumSystemVersion</key><string>14.0</string>
        </dict>
        </plist>
        """
        try plist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        // Locally-generated unsigned bundle: clear quarantine and register with LaunchServices.
        Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        if FileManager.default.fileExists(atPath: lsregister) {
            Shell.run(lsregister, ["-f", app.path])
        }

        return Generated(app: app, launcher: launcher)
    }

    /// Best-effort absolute path to the running `cellar` binary (for the .app launcher script).
    public static func resolveCellarBinary() -> String {
        if let installed = Shell.which("cellar") { return installed }
        return ProcessInfo.processInfo.arguments.first.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        } ?? "/usr/local/bin/cellar"
    }
}
