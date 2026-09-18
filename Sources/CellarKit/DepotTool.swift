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
    /// storage*, whose location is hashed and derived by the runtime. Some runtimes derive it from
    /// `HOME`, and pinning it keeps anything they write somewhere Cellar owns. DepotDownloader 3.4.0
    /// does **not** honour it on macOS — its store lands under `~/Library/Application Support` —
    /// which is why `storedSessionFiles` searches every root rather than trusting this one.
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
            // `-remember-password` is what makes DepotDownloader ask Steam for a *persistent*
            // session (`IsPersistentSession`). Without it the QR login hands back a short-lived
            // token: the ownership checks straight after signing in worked, and three minutes later
            // Steam refused it with AccessDenied — so the sign-in evaporated on its own.
            case .qr: return ["-qr", "-remember-password"]
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
    /// smallest possible job (`-app 480`, Valve's free Spacewar SDK sample, into a scratch dir) and,
    /// when the output is streamed, stop as soon as the session is established. The point is the side effect: DepotDownloader
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
            //
            // Stop at the licence list. Left alone the tool goes on to fetch Spacewar, and the
            // player — who has already approved on their phone — watches a spent QR code while it does.
            var established = false
            _ = try? runStreaming(args: args, output: { line in
                if SteamAccount.isSessionEstablished(line) { established = true }
                output(line)
            }, stopWhen: { established })
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
    ///
    /// Safe to run several at once, which is how `StoreLibrary.refreshSteam` asks about a whole
    /// library in about the time one check takes — provided each concurrent run passes its own
    /// `loginID`. Steam ends a session when another signs in with the same logon id, and every
    /// DepotDownloader run defaults to the same one.
    public static func access(appID: Int, credentials: Credentials, loginID: UInt32? = nil,
                              timeout: TimeInterval = 90) -> Access {
        guard (try? install()) != nil else { return .unknown("DepotDownloader isn't installed") }
        // One scratch directory per app: every run deletes its own when it is done, and a shared
        // one would be pulled out from under a check still running beside it.
        let scratch = Paths.cache.appendingPathComponent("ownership/\(appID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var args = ["-app", "\(appID)", "-os", "windows", "-osarch", "64",
                    "-manifest-only", "-dir", scratch.path]
        args += credentials.arguments
        if let loginID { args += ["-loginid", "\(loginID)"] }

        // Steam turns away a sign-in when the account already holds as many sessions as it allows —
        // `AlreadyLoggedInElsewhere`, with nothing wrong with the account. Checks are short-lived,
        // so one frees up within seconds and the question is asked again rather than left
        // unanswered.
        var result: Access = .unknown("Steam didn't answer")
        for attempt in 1...busyAttempts {
            let verdict = probe(args: args, timeout: timeout)
            guard verdict == .busy else {
                result = verdict?.access ?? .unknown("Steam didn't answer")
                break
            }
            result = .unknown("Steam kept turning the sign-in away")
            if attempt < busyAttempts { Thread.sleep(forTimeInterval: 1.5 * Double(attempt)) }
        }

        if case .available = result { sessionRecordLock.withLock { SteamAccount.noteSuccess() } }
        try? FileManager.default.removeItem(at: scratch)
        return result
    }

    static let busyAttempts = 3

    /// One run of the tool, stopped the moment a line settles the question.
    private static func probe(args: [String], timeout: TimeInterval) -> ProbeVerdict? {
        var verdict: ProbeVerdict?
        // Killing the process the moment the verdict is in is what keeps this cheap: a manifest for
        // a large game is tens of megabytes, and none of it is needed to answer the question.
        _ = try? runStreaming(args: args, timeout: timeout) { line in
            sessionRecordLock.withLock { SteamAccount.note(line) }
            if verdict == nil { verdict = probeVerdict(in: line) }
        } stopWhen: { verdict != nil }
        return verdict
    }

    /// What one line of an ownership probe settles, if anything.
    enum ProbeVerdict: Equatable {
        case answer(Access)
        /// Steam turned the sign-in away for now; asking again shortly is expected to work.
        case busy

        var access: Access? { if case .answer(let access) = self { return access }; return nil }
    }

    static func probeVerdict(in line: String) -> ProbeVerdict? {
        if line.contains("is not available from this account") {
            return .answer(.unavailable)
        } else if line.contains("Processing depot") || line.contains("Got manifest request code")
                    || line.contains("Using app branch") {
            return .answer(.available)
        } else if line.contains("Access token was rejected") {
            return .answer(.unknown("your Steam sign-in has expired"))
        } else if line.contains("Couldn't find any depots to download") {
            // Owned, but nothing to fetch for Windows/64-bit — a profile problem, not ownership.
            return .answer(.unknown("Steam lists no Windows depot for this app"))
        } else if line.contains("AlreadyLoggedInElsewhere") {
            return .busy
        }
        return nil
    }

    /// Serialises the read-modify-write of the sign-in record when checks run side by side.
    private static let sessionRecordLock = NSLock()

    // MARK: - Current build

    /// What Steam says is the current build of an app, depot by depot.
    public enum LatestManifests: Sendable, Equatable {
        case manifests([UInt32: UInt64])
        /// No answer — not signed in, no network, the tool failed. Not "up to date".
        case unknown(String)
    }

    /// Ask Steam which manifest each of an app's Windows depots is on today, without downloading
    /// the game. Same `-manifest-only` question as `access`, and like it, the run is stopped the
    /// moment every depot has named its manifest.
    ///
    /// Into a scratch directory, never the game's: a manifest-only run writes its own
    /// `depot.config`, and in the game's folder that would overwrite the record of what is installed.
    /// One directory per run, because the app's background check and a launch can ask about the
    /// same game at once — and a logon id of its own, so a check never signs out a download.
    public static func latestManifests(appID: Int, credentials: Credentials,
                                       timeout: TimeInterval = 90) -> LatestManifests {
        guard (try? install()) != nil else { return .unknown("DepotDownloader isn't installed") }
        let scratch = Paths.cache.appendingPathComponent("update-check/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        var args = ["-app", "\(appID)", "-os", "windows", "-osarch", "64",
                    "-manifest-only", "-dir", scratch.path]
        args += credentials.arguments
        args += ["-loginid", "\(updateCheckLoginIDBase + UInt32.random(in: 0..<256))"]

        var listing = DepotManifests.Listing()
        do {
            try runStreaming(args: args, timeout: timeout) { line in
                SteamAccount.note(line)
                listing.read(line)
            } stopWhen: { listing.isComplete }
        } catch {
            if let failure = listing.failure { return .unknown(failure) }
            return .unknown("DepotDownloader failed: \(CellarLog.describe(error))")
        }
        if let failure = listing.failure { return .unknown(failure) }
        guard listing.isComplete else { return .unknown("Steam didn't answer in time") }
        SteamAccount.noteSuccess()
        return .manifests(listing.manifests)
    }

    /// Logon ids for update checks ("CEU" + a random byte) — apart from DepotDownloader's default,
    /// which downloads use, and from the ownership checks' range.
    static let updateCheckLoginIDBase: UInt32 = 0x4345_5500

    /// Whether a DepotDownloader run is writing into `directory` right now — including one left
    /// behind by a `cellar` that was stopped: the tool is its own process and outlives its parent.
    /// Two runs in one game folder is two writers on the same files, so anything about to start one
    /// asks this first.
    public static func isDownloading(into directory: URL) -> Bool {
        // The `sh -c` line itself carries both words; excluding `ps -axo` rules it out.
        Shell.run("/bin/sh", ["-c",
            "ps -axo command | grep -v 'ps -axo' | grep -F DepotDownloader | grep -qF -- \"$0\"",
            directory.path]).succeeded
    }

    // MARK: - The stored session

    /// Whether DepotDownloader holds a token, so a download needs no sign-in.
    ///
    /// Presence is the only thing that can honestly be claimed — whether the token is still *valid*
    /// is knowable only by using it, which is what `SteamAccount.note` watches for.
    /// Every account name holding a token, lowercased (DepotDownloader's keys are case-insensitive).
    ///
    /// A store *file* is not a session: when Steam refuses a token, DepotDownloader deletes it from
    /// the store and rewrites the file — a few bytes, no tokens. Counting the file would keep saying
    /// "signed in" about an account whose session is gone.
    public static var storedAccountNames: Set<String> {
        Set(storedAccounts.flatMap(\.names).map { $0.lowercased() })
    }

    /// The accounts DepotDownloader holds a token for, with when each store was last written —
    /// newest store first. Names only; the one reader of a token is `refreshToken(for:)`.
    static var storedAccounts: [(names: [String], modified: Date)] {
        storedSessionFiles.map { file in
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return (DepotAccountStore.accountNames(in: file), modified)
        }
        .sorted { $0.modified > $1.modified }
    }

    /// The stored refresh token for `account`, newest store first. Read for one purpose only —
    /// handing the Windows client in a bottle the same session (`SteamClientSession`) — and never
    /// written anywhere but that client's encrypted `local.vdf` entry.
    static func refreshToken(for account: String) -> String? {
        storedSessionFiles
            .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .lazy.compactMap { DepotAccountStore.refreshToken(for: account, in: $0.0) }.first
    }

    /// Where `storedSessionFiles` looks, in order.
    static var sessionSearchRoots: [URL] { [home, isolatedStorageRoot, isolatedStorageFallback] }

    /// Every `account.config` that could hold this machine's Steam token.
    ///
    /// Cellar pins `HOME` so the store lands somewhere it owns, but .NET's isolated storage is
    /// hashed and its root has moved between runtimes — so a *successful* sign-in must be
    /// recognised wherever the file ended up. Saying "not signed in" straight after somebody
    /// scanned a QR code would be the worst possible answer, and it is the one a single hard-coded
    /// path risks giving.
    static var storedSessionFiles: [URL] {
        var found: [URL] = []
        for root in sessionSearchRoots {
            guard let e = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for case let file as URL in e where file.lastPathComponent == "account.config" {
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 0 { found.append(file) }
            }
        }
        return found
    }

    /// Where DepotDownloader 3.4.0 (.NET 8) really writes its store on macOS. .NET resolves this
    /// folder from the user database, not from `HOME`, so pinning `HOME` does not move it — and a
    /// sign-in that landed here while Cellar looked elsewhere was reported as never having happened.
    static var isolatedStorageRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/IsolatedStorage", isDirectory: true)
    }

    /// Where older .NET runtimes put isolated storage on Unix.
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
