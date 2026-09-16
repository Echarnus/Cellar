import Foundation

/// Steam's first self-update, done where the player can see it: in Cellar.
///
/// `SteamSetup.exe` only drops a bootstrapper. The first time that bootstrapper runs it downloads
/// the real client — several hundred megabytes, in more than one pass — and draws its own little
/// Windows progress window to say so, in the middle of a Mac, looking like nothing else on screen.
/// So Cellar runs that first start itself with the Dock shim told to keep the client's windows off
/// screen (`DockShim.environment(hidingWindowsOf:)`): the window exists but is never shown, the
/// numbers it would have shown are read out of Steam's own `bootstrap_log.txt`, and Cellar's
/// install bar or launch window shows them instead.
///
/// Not Wine's null display driver, which keeps `wineboot`'s box away: the bootstrapper refuses to
/// run without a real window ("failed to initialize update status ui, or create initial window")
/// and sits there doing nothing.
public enum SteamClientUpdate {
    /// Steam's own log of every bootstrapper session, appended to, never rotated by the updater.
    public static func logFile(inSteamDirectory dir: URL) -> URL {
        dir.appendingPathComponent("logs/bootstrap_log.txt")
    }

    /// Whether the client is the real, updated one.
    ///
    /// Not `steamclient64.dll`: that is already on disk after the *first* pass, while a second pass
    /// (the 64-bit client) is still to come. The bootstrapper writes this manifest only once the
    /// 64-bit client is installed, which is the last thing it does before starting Steam proper.
    public static func isComplete(inSteamDirectory dir: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("package/steam_client_win64.installed").path)
    }

    /// How much of the current download pass is down, from one bootstrap log line.
    ///
    /// Steam writes this line in the player's language — `Downloading update (5,646 of 336,229
    /// KB)...`, `Update wordt gedownload (5.646 van 336.229 KB)...` — so it is read by shape, not by
    /// words: two numbers in the parentheses closing the line, the second the total. Group
    /// separators vary by locale too (`,` `.` `'` or a narrow no-break space), and these are
    /// kilobytes, never fractions, so every non-digit inside a number is simply dropped.
    public static func fraction(in line: String) -> Double? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = downloadLine.firstMatch(in: line, range: range),
              let doneRange = Range(match.range(at: 1), in: line),
              let totalRange = Range(match.range(at: 2), in: line),
              let done = Double(line[doneRange].filter(\.isNumber)),
              let total = Double(line[totalRange].filter(\.isNumber)),
              total > 0, done <= total else { return nil }
        return done / total
    }

    /// `(<number> <word(s)> <number> <unit>)` closing the line. ICU's `\s` covers every Unicode space.
    private static let downloadLine = try! NSRegularExpression(
        pattern: #"\(\s*(\d(?:[\d.,'\s]*\d)?)\s*\D+?\s*(\d(?:[\d.,'\s]*\d)?)\s*[^\d\s()]+\s*\)\.*\s*$"#)

    /// Run the first update with nothing on screen, reporting how far the download is.
    ///
    /// `fraction` gets the current pass's share, or nil while Steam is checking, unpacking or
    /// installing — there is no honest number for those. Returns once the client is complete and
    /// the invisible session has been shut down again, so the next start draws its windows normally.
    ///
    /// When another bottle's Steam is already updating the shared install, that one is followed
    /// instead of starting a second updater over the same files.
    public static func run(runner: WineRunner, steamDirectory dir: URL,
                           fraction: (Double?) -> Void = { _ in },
                           progress: (String) -> Void = { _ in },
                           stallTimeout: TimeInterval = 5 * 60) throws {
        guard !isComplete(inSteamDirectory: dir) else { return }
        let log = logFile(inSteamDirectory: dir)
        var offset = fileSize(log)

        let someoneElseIsUpdating = SteamBottle.isRunning && modifiedWithin(log, seconds: 15)
        if someoneElseIsUpdating {
            progress("Steam is already updating in another bottle — following that one.")
        } else {
            progress("Updating Steam — its first start downloads the full client from Valve.")
            CellarLog.info(.store, "Running Steam's first update headless in '\(runner.prefix.lastPathComponent)'.",
                           subject: runner.prefix.lastPathComponent)
            let env = DockShim.environment(hidingWindowsOf: GameStore.steam.descriptor.clientProcessNames)
            if env.isEmpty {
                CellarLog.warn(.store, "The Dock shim is not installed, so Steam's update window will show.")
            }
            try runner.spawn([SteamBottle.steamExecutable(in: runner.prefix).path, "-silent"],
                             extraEnv: env,
                             log: Paths.logs.appendingPathComponent("steam-update-\(runner.prefix.lastPathComponent).log"))
        }
        // Only a session Cellar started is Cellar's to close.
        defer { if !someoneElseIsUpdating { runner.killServer() } }

        fraction(nil)
        var lastReported: Double?
        var lastActivity = Date()
        var quietSinceComplete: Date?
        while true {
            Thread.sleep(forTimeInterval: 0.5)
            let lines = readLines(from: log, offset: &offset)
            if !lines.isEmpty { lastActivity = Date() }
            // While a pass downloads, every line it writes carries the numbers; any other line —
            // unpacking, installing, restarting for the next pass — has none to show.
            for line in lines {
                let now = SteamClientUpdate.fraction(in: line)
                guard now != lastReported else { continue }
                fraction(now)
                // The terminal gets a line per tenth rather than one per log line.
                if let now, Int(now * 10) != lastReported.map({ Int($0 * 10) }) {
                    progress("Downloading Steam's client… \(Int(now * 10) * 10)%")
                }
                lastReported = now
            }

            if isComplete(inSteamDirectory: dir) {
                // Steam restarts itself once more after installing and checks for anything newer;
                // a few quiet seconds say there is no further pass coming.
                if !lines.isEmpty || quietSinceComplete == nil { quietSinceComplete = Date() }
                if let since = quietSinceComplete, Date().timeIntervalSince(since) > 12 {
                    progress("Steam is up to date.")
                    CellarLog.info(.store, "Steam's first update finished.")
                    return
                }
            } else if Date().timeIntervalSince(lastActivity) > stallTimeout {
                throw CellarError.ioFailure(
                    "Steam's first update stopped making progress. Check your connection and try again — Steam's own log is at \(log.path)")
            }
        }
    }

    // MARK: - Reading the log

    static func fileSize(_ url: URL) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    static func modifiedWithin(_ url: URL, seconds: TimeInterval) -> Bool {
        guard let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else { return false }
        return Date().timeIntervalSince(date) < seconds
    }

    /// Complete lines appended since `offset`, which is advanced past them. A line still being
    /// written is left for the next read.
    static func readLines(from url: URL, offset: inout UInt64) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { offset = 0 }   // replaced underneath us: start over
        guard size > offset else { return [] }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), let lastNewline = data.lastIndex(of: 0x0A) else { return [] }
        let complete = data[data.startIndex...lastNewline]
        offset += UInt64(complete.count)
        // Steam writes UTF-8; a stray byte must not cost the whole batch.
        return String(decoding: complete, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }
}
