import Foundation

/// DepotDownloader (SteamRE, GPL-2.0): downloads the files of a game you own directly from Steam's
/// content servers, authenticating with your Steam account — no Windows Steam client to install or
/// manage. Cellar uses the native **arm64** self-contained build, so this step is ARM-native and
/// survives the Rosetta sunset. It is the Proton-like "just fetch the game" path; whether the game
/// then needs Steam *running* to play is a per-title DRM question (see the profile's `needs_live_steam`).
public enum DepotTool {
    /// Pinned native-arm64 release. (A newer pin is a one-line change; the API is stable.)
    static let downloadURL =
        "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-macos-arm64.zip"

    public static var root: URL { Paths.appSupport.appendingPathComponent("tools/depotdownloader", isDirectory: true) }
    public static var binary: URL { root.appendingPathComponent("DepotDownloader") }

    public static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: binary.path) }

    /// Download + unpack the tool (idempotent).
    @discardableResult
    public static func install(progress: (String) -> Void = { _ in }) throws -> URL {
        if isInstalled { return binary }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let zip = Paths.cache.appendingPathComponent("depotdownloader-macos-arm64.zip")
        progress("Downloading DepotDownloader (native arm64)…")
        try Downloader.fetch(downloadURL, to: zip)
        progress("Unpacking…")
        try Archive.unzip(zip, to: root)
        try? FileManager.default.removeItem(at: zip)
        // Self-contained single-file publish: make it runnable and clear the quarantine flag.
        Shell.run("/bin/chmod", ["+x", binary.path])
        Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", root.path])
        guard isInstalled else { throw CellarError.ioFailure("DepotDownloader missing after unpack.") }
        return binary
    }

    /// Download an owned game's **Windows** files into `directory`, authenticating as `username`
    /// (Steam Guard / 2FA is prompted interactively — this must run on a real terminal).
    /// `depotAppID` is usually the game's own appid. Streams DepotDownloader's output.
    public static func fetch(appID: Int, into directory: URL, username: String,
                             depot: Int? = nil, extraArgs: [String] = []) throws {
        try install()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var args = ["-app", "\(appID)", "-os", "windows", "-osarch", "64",
                    "-dir", directory.path, "-username", username, "-remember-password"]
        if let depot { args += ["-depot", "\(depot)"] }
        args += extraArgs
        let p = Process()
        p.executableURL = binary
        p.arguments = args
        p.currentDirectoryURL = root
        try p.run()          // inherits stdio so the Steam Guard prompt reaches the user
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw CellarError.ioFailure("DepotDownloader exited \(p.terminationStatus).")
        }
    }
}
