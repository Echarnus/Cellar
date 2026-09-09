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

    /// How the player proves who they are.
    ///
    /// `qr` is Steam's own device-authorization flow (`IAuthenticationService/BeginAuthSessionViaQR`),
    /// the same one the real client shows: Cellar never sees a password, and approval happens in the
    /// Steam mobile app. That makes it the default for anything player-facing. `password` stays for
    /// scripted use and for accounts without the mobile app.
    public enum Credentials {
        case qr
        case password(username: String)

        var arguments: [String] {
            switch self {
            case .qr: return ["-qr"]
            case .password(let username): return ["-username", username, "-remember-password"]
            }
        }
    }

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

    /// Download an owned game's **Windows** files into `directory`.
    ///
    /// With `.password`, Steam Guard is prompted on the terminal, so this must run with a real stdin.
    /// With `.qr`, nothing is typed at all: DepotDownloader prints a QR challenge, `output` receives
    /// every line as it arrives, and a GUI can turn `challengeURL(in:)` into a scannable code.
    public static func fetch(appID: Int, into directory: URL, credentials: Credentials,
                            depot: Int? = nil, extraArgs: [String] = [],
                            output: ((String) -> Void)? = nil) throws {
        try install()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var args = ["-app", "\(appID)", "-os", "windows", "-osarch", "64", "-dir", directory.path]
        args += credentials.arguments
        if let depot { args += ["-depot", "\(depot)"] }
        args += extraArgs

        guard let output else {
            // No observer: inherit stdio so an interactive Steam Guard prompt reaches the player.
            let p = Process()
            p.executableURL = binary
            p.arguments = args
            p.currentDirectoryURL = root
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw CellarError.ioFailure("DepotDownloader exited \(p.terminationStatus).")
            }
            return
        }
        try runStreaming(args: args, output: output)
    }

    /// Sign in only — no download. Steam has no "log in" verb of its own here, so we ask for the
    /// smallest possible job (`-app 480`, Valve's free Spacewar SDK sample, into a scratch dir) and
    /// stop as soon as the session is established. The point is the side effect: DepotDownloader
    /// writes a refresh token to its own account store, so every later download is silent.
    public static func signIn(credentials: Credentials, output: ((String) -> Void)? = nil) throws {
        try install()
        let scratch = Paths.cache.appendingPathComponent("steam-signin", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var args = ["-app", "480", "-os", "windows", "-osarch", "64", "-dir", scratch.path]
        args += credentials.arguments
        if let output {
            try runStreaming(args: args, output: output)
        } else {
            let p = Process()
            p.executableURL = binary
            p.arguments = args
            p.currentDirectoryURL = root
            try p.run()
            p.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: scratch)
    }

    /// Whether DepotDownloader already holds a session, so a download needs no sign-in. Its account
    /// store is a single file beside the binary; presence is the only thing we can honestly claim —
    /// whether the token is still *valid* is only knowable by using it.
    public static var hasStoredSession: Bool {
        let store = root.appendingPathComponent("account.config")
        guard let size = try? FileManager.default.attributesOfItem(atPath: store.path)[.size] as? Int else {
            return false
        }
        return size > 0
    }

    /// Forget the stored Steam session (sign out of the download path).
    public static func forgetSession() throws {
        for name in ["account.config", "depot.config"] {
            let url = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }


    /// Run the tool with its output piped back line by line, so a caller can watch for the QR
    /// challenge and for progress without waiting for exit.
    private static func runStreaming(args: [String], output: @escaping (String) -> Void) throws {
        let p = Process()
        p.executableURL = binary
        p.arguments = args
        p.currentDirectoryURL = root
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()

        var buffer = Data()
        let handle = pipe.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            // DepotDownloader draws progress with \r; treat both terminators as line ends.
            while let idx = buffer.firstIndex(where: { $0 == UInt8(ascii: "\n") || $0 == UInt8(ascii: "\r") }) {
                let line = String(data: buffer[buffer.startIndex..<idx], encoding: .utf8) ?? ""
                buffer.removeSubrange(buffer.startIndex...idx)
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { output(line) }
            }
        }
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) { output(line) }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw CellarError.ioFailure("DepotDownloader exited \(p.terminationStatus).")
        }
    }
}
