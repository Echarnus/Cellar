import Foundation

/// DepotDownloader (SteamRE, GPL-2.0): downloads the files of a game you own directly from Steam's
/// content servers, authenticating with your Steam account — no Windows Steam client to install or
/// manage. Cellar uses the native **arm64** self-contained build, so this step is ARM-native and
/// survives the Rosetta sunset. It is the Proton-like "just fetch the game" path; whether the game
/// then needs Steam *running* to play is a per-title DRM question (see the profile's `needs_live_steam`).
///
/// It is also the holder of Cellar's single Steam credential — see `SteamAccount`, which is the
/// type player-facing code should talk to. Nothing here decides policy; it runs the tool.
public enum DepotTool {
    /// Pinned native-arm64 release. (A newer pin is a one-line change; the API is stable.)
    static let downloadURL =
        "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-macos-arm64.zip"

    public static var root: URL { Paths.appSupport.appendingPathComponent("tools/depotdownloader", isDirectory: true) }
    public static var binary: URL { root.appendingPathComponent("DepotDownloader") }

    /// A home directory of Cellar's own, handed to every DepotDownloader run.
    ///
    /// This is load-bearing, not tidiness. DepotDownloader keeps its Steam token in .NET *isolated
    /// storage*, whose location is derived from the process's `HOME` and hashed — so with the real
    /// home directory, Cellar could neither tell that a session existed nor delete it. It looked
    /// beside the binary for an `account.config` that .NET never writes there, which meant "signed
    /// in for downloads" was permanently false, sign-out did nothing, and every download re-asked
    /// for a QR scan. Pinning `HOME` puts the store somewhere Cellar owns, so the session can be
    /// seen, reused and genuinely revoked.
    public static var home: URL { root.appendingPathComponent("home", isDirectory: true) }

    public static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: binary.path) }

    /// How the player proves who they are.
    ///
    /// `qr` is Steam's own device-authorization flow (`IAuthenticationService/BeginAuthSessionViaQR`),
    /// the same one the real client shows: Cellar never sees a password, and approval happens in the
    /// Steam mobile app. It is used exactly once, by `SteamAccount.signIn`.
    ///
    /// `session` is every run after that: the token stored under the account name is reused with no
    /// prompt at all. `password` stays for scripted use and for accounts without the mobile app.
    public enum Credentials {
        case qr
        case session(username: String)
        case password(username: String)
        /// Steam's anonymous account — enough for free, unrestricted apps, and for nothing else.
        case anonymous

        var arguments: [String] {
            switch self {
            case .qr: return ["-qr"]
            case .session(let username), .password(let username):
                return ["-username", username, "-remember-password"]
            case .anonymous: return []
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
    /// Everything else is silent: `.session` reuses the stored token, and `.qr` draws a challenge
    /// that `output` receives line by line so a GUI can render it.
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
            try runInheritingIO(args: args)
            SteamAccount.noteSuccess()
            return
        }
        try runStreaming(args: args) { line in
            SteamAccount.note(line)
            output(line)
        }
        SteamAccount.noteSuccess()
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
            // A sign-in that fails is answered by the caller reading the state, not by a throw:
            // "you closed the app without scanning" is not an error worth a stack of red text.
            _ = try? runStreaming(args: args, output: output)
        } else {
            try? runInheritingIO(args: args)
        }
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: - Ownership

    /// What Steam says about one app for the signed-in account.
    public enum Access: Sendable, Equatable {
        /// Steam will hand these files over — the account owns it (or it is free to everyone).
        case available
        /// Steam refused: this account has no licence for it.
        case unavailable
        /// Cellar could not get an answer — not signed in, no network, the tool failed. Never
        /// rendered as "you don't own this": an unanswered question is not a "no".
        case unknown(String)
    }

    /// Ask Steam whether this account may download an app, without downloading it.
    ///
    /// `-manifest-only` stops before any game files move, and DepotDownloader checks the account's
    /// licences before it fetches anything — so the answer arrives in the first few lines and the
    /// process is killed as soon as it does. That is deliberately the *same* question as "can I
    /// install this", asked of the same credential that would do the installing: it covers a lapsed
    /// family-share or a region lock, which a list of owned app ids would not.
    public static func access(appID: Int, credentials: Credentials, timeout: TimeInterval = 90) -> Access {
        guard (try? install()) != nil else { return .unknown("DepotDownloader isn't installed") }
        let scratch = Paths.cache.appendingPathComponent("ownership", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var args = ["-app", "\(appID)", "-os", "windows", "-osarch", "64",
                    "-manifest-only", "-dir", scratch.path]
        args += credentials.arguments

        var verdict: Access?
        // Killing the process the moment the verdict is in is what keeps this cheap: a manifest for
        // a large game is tens of megabytes, and none of it is needed to answer the question.
        _ = try? runStreaming(args: args, timeout: timeout) { line in
            SteamAccount.note(line)
            guard verdict == nil else { return }
            if line.contains("is not available from this account") {
                verdict = .unavailable
            } else if line.contains("Processing depot") || line.contains("Got manifest request code")
                        || line.contains("Using app branch") {
                verdict = .available
            } else if line.contains("Access token was rejected") {
                verdict = .unknown("your Steam sign-in has expired")
            } else if line.contains("Couldn't find any depots to download") {
                // Owned, but nothing to fetch for Windows/64-bit — a profile problem, not ownership.
                verdict = .unknown("Steam lists no Windows depot for this app")
            }
        } stopWhen: { verdict != nil }

        if case .available = verdict { SteamAccount.noteSuccess() }
        try? FileManager.default.removeItem(at: scratch)
        return verdict ?? .unknown("Steam didn't answer")
    }

    // MARK: - The stored session

    /// Whether DepotDownloader holds a token, so a download needs no sign-in.
    ///
    /// Presence is the only thing that can honestly be claimed — whether the token is still *valid*
    /// is knowable only by using it, which is what `SteamAccount.note` watches for.
    public static var hasStoredSession: Bool { !storedSessionFiles.isEmpty }

    /// Every `account.config` that could hold this machine's Steam token.
    ///
    /// Cellar pins `HOME` so the store lands somewhere it owns, but .NET's isolated storage is
    /// hashed and its root has moved between runtimes — so a *successful* sign-in must be
    /// recognised wherever the file ended up. Saying "not signed in" straight after somebody
    /// scanned a QR code would be the worst possible answer, and it is the one a single hard-coded
    /// path risks giving.
    static var storedSessionFiles: [URL] {
        var found: [URL] = []
        for root in [home, isolatedStorageFallback] {
            guard let e = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for case let file as URL in e where file.lastPathComponent == "account.config" {
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 0 { found.append(file) }
            }
        }
        return found
    }

    /// Where .NET puts isolated storage when `HOME` is the real one — the location Cellar used to
    /// be blind to.
    static var isolatedStorageFallback: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/IsolatedStorage", isDirectory: true)
    }

    /// Forget the stored Steam session (sign out of the download path).
    ///
    /// Cellar's private home for the tool goes wholesale. Outside it, only the token *files* are
    /// removed and never the surrounding directory — isolated storage is shared with any other .NET
    /// program on this Mac, and signing out of Steam is no licence to delete their state.
    public static func forgetSession() throws {
        let strays = storedSessionFiles.filter { !$0.path.hasPrefix(home.path) }
        if FileManager.default.fileExists(atPath: home.path) {
            try FileManager.default.removeItem(at: home)
        }
        for file in strays { try? FileManager.default.removeItem(at: file) }
    }

    // MARK: - Running the tool

    /// Every invocation goes through here, so the pinned `HOME` can never be forgotten by one
    /// call site — which is exactly how the session went missing before.
    private static func process(_ args: [String]) throws -> Process {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = binary
        p.arguments = args
        p.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = home.path
        p.environment = env
        return p
    }

    private static func runInheritingIO(args: [String]) throws {
        let p = try process(args)
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw CellarError.ioFailure("DepotDownloader exited \(p.terminationStatus).")
        }
    }

    /// Run the tool with its output piped back line by line, so a caller can watch for the QR
    /// challenge and for progress without waiting for exit.
    ///
    /// `stopWhen` is polled after each line: when it returns true the process is terminated and the
    /// run counts as a success. That is how an ownership check answers in seconds instead of
    /// downloading a manifest it will throw away.
    @discardableResult
    private static func runStreaming(args: [String], timeout: TimeInterval? = nil,
                                     output: @escaping (String) -> Void,
                                     stopWhen: () -> Bool = { false }) throws -> Bool {
        let p = try process(args)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        // No stdin. Nothing on this path can answer a prompt — the app has no terminal — so a tool
        // that decides to ask for a password must fail rather than wait forever. The read loop
        // below only notices a timeout when the next chunk arrives, so a process blocked on input
        // would never be reaped.
        p.standardInput = FileHandle.nullDevice
        try p.run()

        let deadline = timeout.map { Date().addingTimeInterval($0) }
        // The loop below blocks in `availableData`, so it only notices the deadline when the tool
        // says something. A watchdog is what makes the timeout mean anything for a process that has
        // gone quiet — a stalled content server, a connection that never completes.
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak p] in
                if p?.isRunning == true { p?.terminate() }
            }
        }
        var stoppedEarly = false
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
            if stopWhen() { stoppedEarly = true; break }
            if let deadline, Date() > deadline { stoppedEarly = true; break }
        }
        if !stoppedEarly, !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) { output(line) }
        if stoppedEarly {
            p.terminate()
            return true
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw CellarError.ioFailure("DepotDownloader exited \(p.terminationStatus).")
        }
        return false
    }
}
