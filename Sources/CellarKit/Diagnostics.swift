import Foundation

/// Turns the rolling log into something that can be *sent*.
///
/// Three jobs, all in service of "it crashed and I can't tell you why":
/// 1. **Lifecycle bookkeeping** — the app leaves a marker while it is running, so the next start
///    can notice the previous one never got to say goodbye.
/// 2. **Play sessions** — a launch is remembered until the game exits, so the exit can be logged
///    with how long it lasted and whether macOS filed a crash report in the meantime.
/// 3. **The report** — one text file with the machine, the runners, the bottles, the rolling log
///    and the tails of the Wine logs, with personal paths and any secrets stripped out.
public enum Diagnostics {

    // MARK: - Process lifecycle

    /// Marker left behind while the app is running. Its presence at the next start is the only
    /// honest evidence Cellar has that the previous session ended abnormally.
    private static var runMarker: URL { Paths.logs.appendingPathComponent("app-session.marker") }

    /// Call once at start-up. Logs the start, and reports a previous session that never exited
    /// cleanly — with any macOS crash report that lines up with it.
    public static func processDidStart(version: String = CellarVersion.current) {
        try? FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)

        if let previous = try? String(contentsOf: runMarker, encoding: .utf8),
           let started = CellarLog.timestampFormatter.date(from: previous.trimmingCharacters(in: .whitespacesAndNewlines)) {
            CellarLog.warn(.app, "The previous Cellar session (started \(CellarLog.timestampFormatter.string(from: started))) "
                + "ended without shutting down cleanly.")
            for report in crashReports(since: started, matching: ["Cellar"]) {
                CellarLog.error(.app, "macOS filed a crash report for it: \(report.lastPathComponent)")
            }
        }

        CellarLog.info(.app, "Cellar \(version) started — macOS \(SystemEnvironment.macOSVersionString), "
            + "\(SystemEnvironment.chipBrand.isEmpty ? "unknown chip" : SystemEnvironment.chipBrand)")
        try? Data(CellarLog.timestampFormatter.string(from: Date()).utf8).write(to: runMarker)
    }

    /// Call on a clean quit. Removing the marker is what makes the next start's warning meaningful.
    public static func processWillExit() {
        CellarLog.info(.app, "Cellar quit.")
        try? FileManager.default.removeItem(at: runMarker)
    }

    // MARK: - Play sessions

    private struct PlaySession {
        let slug: String
        let name: String
        let route: String
        let startedAt: Date
    }

    private static let lock = NSLock()
    /// Keyed by slug, not a single slot: one process can have two games up (the app launches each
    /// through its own `cellar launch`, but nothing stops two launches sharing a process), and the
    /// second one must not erase the first one's start time.
    private static var open: [String: PlaySession] = [:]

    /// A game is up. Remembered in-process so the matching exit can be logged with a duration —
    /// `cellar launch` starts the game and waits for it in the same process.
    public static func playSessionBegan(slug: String, name: String, route: String) {
        lock.lock()
        open[slug] = PlaySession(slug: slug, name: name, route: route, startedAt: Date())
        lock.unlock()
        CellarLog.info(.session, "\(name) is up (\(route)).", subject: slug)
    }

    /// The game is gone. Logs how long it ran, and — when that was suspiciously short — the
    /// evidence a reader would otherwise have to go hunting for.
    ///
    /// Cellar cannot see a Windows exit code through Wine, so it never *claims* a crash: it
    /// reports the fact (gone after 14 seconds) and what it found alongside it.
    public static func playSessionEnded(slug: String, name: String, processNeedles: [String] = []) {
        lock.lock()
        let session = open.removeValue(forKey: slug)
        lock.unlock()

        guard let session else {
            CellarLog.info(.session, "\(name) exited.", subject: slug)
            return
        }

        let seconds = Int(Date().timeIntervalSince(session.startedAt))
        let played = humanDuration(seconds)

        if seconds < 90 {
            CellarLog.warn(.session, "\(name) exited after \(played) — early enough that it likely "
                + "failed rather than being quit.", subject: slug)
            for line in wineLogTail(slug: slug, lines: 5) {
                CellarLog.debug(.session, "Wine log: \(line)", subject: slug)
            }
            let needles = processNeedles.isEmpty ? [name] : processNeedles
            for report in crashReports(since: session.startedAt, matching: needles + ["wine"]) {
                CellarLog.error(.session, "macOS crash report filed during this session: "
                    + report.lastPathComponent, subject: slug)
            }
        } else {
            CellarLog.info(.session, "\(name) exited after \(played).", subject: slug)
        }
    }

    static func humanDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }

    // MARK: - Evidence on disk

    /// macOS crash reports filed since `since` whose name mentions one of `needles` (an exe name,
    /// "wine", "Cellar"). Both the user and the system report directories are searched.
    public static func crashReports(since: Date, matching needles: [String], limit: Int = 5) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directories = [
            home.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true),
            URL(fileURLWithPath: "/Library/Logs/DiagnosticReports", isDirectory: true),
        ]
        let stems = needles
            .map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.lowercased() }
            .filter { $0.count >= 3 }

        var found: [(URL, Date)] = []
        for directory in directories {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for entry in entries {
                let name = entry.lastPathComponent.lowercased()
                guard name.hasSuffix(".ips") || name.hasSuffix(".crash"),
                      stems.contains(where: { name.contains($0) }),
                      let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                          .contentModificationDate,
                      modified >= since.addingTimeInterval(-5)
                else { continue }
                found.append((entry, modified))
            }
        }
        return found.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// Wine's own output for a game, newest file first. These are the per-launch logs
    /// `WineRunner.spawn` writes — the place `err:` lines actually live.
    public static func wineLogs(slug: String? = nil, limit: Int = 5) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: Paths.logs, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return entries
            .filter { $0.pathExtension == "log" && !$0.lastPathComponent.hasPrefix("cellar.log") }
            .filter { slug == nil || $0.lastPathComponent.contains(slug!) }
            .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// The last `lines` non-empty lines of the newest Wine log for a game.
    public static func wineLogTail(slug: String, lines: Int) -> [String] {
        guard let url = wineLogs(slug: slug, limit: 1).first,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .suffix(lines)
    }

    // MARK: - The report

    /// Default file name — dated, so a player can send two of them without confusion.
    public static var suggestedReportName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "cellar-diagnostics-\(formatter.string(from: Date())).txt"
    }

    /// Write the report somewhere the player can find it. Defaults to the Desktop, because the
    /// next thing they will do is drag it into a bug report.
    @discardableResult
    public static func exportReport(to destination: URL? = nil,
                                    cellarVersion: String = CellarVersion.current) throws -> URL {
        let url = destination ?? defaultReportURL()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try report(cellarVersion: cellarVersion).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            CellarLog.failure(.diagnostics, "Could not write the diagnostics report", error)
            throw CellarError.ioFailure("Could not write the report to \(url.path): \(error.localizedDescription)")
        }
        CellarLog.info(.diagnostics, "Wrote a diagnostics report to \(url.lastPathComponent).")
        return url
    }

    private static func defaultReportURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let directory = FileManager.default.fileExists(atPath: desktop.path) ? desktop : home
        return directory.appendingPathComponent(suggestedReportName)
    }

    /// Everything worth knowing about this machine and the last few sessions, as plain text.
    /// Redacted: no home paths, no account names, nothing that looks like a token.
    public static func report(cellarVersion: String = CellarVersion.current) -> String {
        var out: [String] = []
        out.append("Cellar diagnostics")
        out.append("Cellar \(cellarVersion) · generated \(CellarLog.timestampFormatter.string(from: Date()))")
        out.append("Paths are shown relative to your home folder; account names and tokens are removed.")
        out.append("")

        out.append(section("Machine"))
        for check in SystemEnvironment.diagnostics() {
            let mark: String
            switch check.status {
            case .ok: mark = "[ok]  "
            case .warn: mark = "[warn]"
            case .fail: mark = "[fail]"
            case .info: mark = "[info]"
            }
            out.append("\(mark) \(check.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(check.detail)")
        }
        out.append("")

        out.append(section("Runners"))
        let runners = RunnerManager.installed()
        if runners.isEmpty {
            out.append("(none installed)")
        } else {
            for runner in runners {
                out.append("\(runner.spec.id)  \(runner.spec.displayName)  "
                    + "d3dmetal=\(runner.hasD3DMetal ? "yes" : "no")")
            }
        }
        out.append("")

        out.append(section("Bottles"))
        let bottles = (try? PrefixManager.list()) ?? []
        if bottles.isEmpty {
            out.append("(none created)")
        } else {
            for bottle in bottles {
                out.append("\(bottle.name)  runner=\(bottle.runner)  backend=\(bottle.backend)")
            }
        }
        out.append("")

        // Sign-in *state* only — never which account, that is nobody's business but the player's.
        out.append(section("Store accounts"))
        out.append("Steam  shared install: \(SteamBottle.isSharedInstallPresent ? "present" : "none")"
            + ", signed in: \(SteamBottle.sharedLoggedInAccount != nil ? "yes" : "no")")
        out.append("GOG    signed in: \(GOGAuth.isSignedIn ? "yes" : "no")")
        out.append("Battle.net  sign-in state is not observable — Cellar does not track it.")
        out.append("")

        let crashes = crashReports(since: Date().addingTimeInterval(-7 * 24 * 3600),
                                   matching: ["wine", "Cellar"], limit: 8)
        out.append(section("Crash reports (last 7 days)"))
        out.append(crashes.isEmpty ? "(none found)"
                   : crashes.map { "~/Library/Logs/DiagnosticReports/\($0.lastPathComponent)" }.joined(separator: "\n"))
        out.append("")

        // The kept history can be ~1.5 MB. A report is meant to be attached to an issue, so it
        // carries the recent end of it and says so rather than quietly truncating.
        out.append(section("Event log"))
        let all = CellarLog.history().split(separator: "\n", omittingEmptySubsequences: true)
        if all.isEmpty {
            out.append("(empty)")
        } else {
            if all.count > 3000 {
                out.append("(\(all.count - 3000) older entries left out; the full log is in "
                    + "~/Library/Application Support/Cellar/logs)")
            }
            out.append(all.suffix(3000).joined(separator: "\n"))
        }
        out.append("")

        for log in wineLogs(limit: 4) {
            out.append(section("Wine log — \(log.lastPathComponent) (last 120 lines)"))
            let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            let tail = text.split(separator: "\n").suffix(120).joined(separator: "\n")
            out.append(tail.isEmpty ? "(empty)" : tail)
            out.append("")
        }

        return redact(out.joined(separator: "\n")) + "\n"
    }

    private static func section(_ title: String) -> String {
        "== \(title) " + String(repeating: "=", count: max(0, 76 - title.count))
    }

    /// Option values worth keeping in the log: diagnostic, and never private. **Everything else is
    /// redacted, including options that do not exist yet.**
    ///
    /// Listing the *sensitive* names instead is the wrong default, and it failed exactly as you
    /// would expect: it matched only `--long` options, so `fetch-depot -u <steam account>` and
    /// `gog login --code <oauth code>` went into a file players are told to attach to a public bug
    /// report. A list you must remember to extend is a leak waiting for the next option.
    private static let loggableOptionValues: Set<String> = [
        "profile", "backend", "runner", "level", "game", "lines", "limit", "output", "id",
        "l", "o",
    ]

    /// A command line as the log may record it, plus the raw strings that were taken out of it.
    ///
    /// The second half is the point. Redacting the invocation is not enough on its own: anything
    /// *derived* from the same argv can quote a token straight back — ArgumentParser's parse errors
    /// name the offending token verbatim ("Unknown option '-uGluedSecretAccount'"), and that text
    /// was being logged beside the carefully redacted invocation on the same line.
    public struct RedactedCommandLine {
        public let text: String
        /// Longest first, so a whole token is replaced before the value inside it.
        public let removed: [String]

        /// Take out of `message` anything the command line hid, then apply the usual text rules.
        public func scrub(_ message: String) -> String {
            var out = message
            for secret in removed where !secret.isEmpty {
                out = out.replacingOccurrences(of: secret, with: "<redacted>")
            }
            return Diagnostics.redact(out)
        }
    }

    /// Render a command line for the log with every option value stripped unless it is on
    /// `loggableOptionValues`. Positional words — the subcommand and the profile slug — are kept:
    /// no command takes a credential positionally, and they are what makes a log line readable.
    public static func redactCommandLine(_ arguments: [String]) -> RedactedCommandLine {
        var rendered: [String] = []
        var removed: [String] = []
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            index += 1

            guard token.hasPrefix("-"), token != "-", token != "--" else {
                rendered.append(token)
                continue
            }

            let (name, inlineValue) = splitOption(token)
            let keepValue = loggableOptionValues.contains(name.lowercased())
            let flag = token.hasPrefix("--") ? "--\(name)" : "-\(name)"

            // `--name=value`, `-n=value` and the glued `-nvalue` carry the value in the same token.
            if let inlineValue {
                rendered.append(keepValue ? token : "\(flag)=<redacted>")
                if !keepValue { removed += [token, inlineValue] }
                continue
            }

            rendered.append(token)
            // The value is whatever follows that is not another option. A boolean flag has none, so
            // at worst this redacts a positional — one slug lost from one line, never a credential.
            if index < arguments.count, !arguments[index].hasPrefix("-") {
                rendered.append(keepValue ? arguments[index] : "<redacted>")
                if !keepValue { removed.append(arguments[index]) }
                index += 1
            }
        }
        return RedactedCommandLine(text: redact(rendered.joined(separator: " ")),
                                   removed: removed.sorted { $0.count > $1.count })
    }

    /// Split `--name=value` / `-n=value` / `-nvalue` into its name and the value it carries inline.
    private static func splitOption(_ token: String) -> (name: String, value: String?) {
        if token.hasPrefix("--") {
            let body = token.dropFirst(2)
            guard let equals = body.firstIndex(of: "=") else { return (String(body), nil) }
            return (String(body[body.startIndex..<equals]), String(body[body.index(after: equals)...]))
        }
        let body = token.dropFirst()
        guard let first = body.first else { return ("", nil) }
        let rest = body.dropFirst()
        if rest.isEmpty { return (String(first), nil) }
        if rest.hasPrefix("=") { return (String(first), String(rest.dropFirst())) }
        return (String(first), String(rest))
    }

    /// Strip what a player would not want to post in public: their home path, their short user
    /// name, and any `key=value` / `"key": "value"` pair whose key smells like a credential.
    public static func redact(_ text: String) -> String {
        var out = text.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        let user = NSUserName()
        if user.count >= 3 {
            out = out.replacingOccurrences(of: "/Users/\(user)", with: "~")
            out = out.replacingOccurrences(of: user, with: "<user>")
        }
        let secretKey = "(?i)(token|refresh_token|access_token|password|passwd|secret|api[_-]?key|authorization|cookie|session|code|auth|pin|guard)"
        for pattern in ["\(secretKey)\\s*[=:]\\s*\"[^\"]*\"", "\(secretKey)\\s*[=:]\\s*\\S+"] {
            out = out.replacingOccurrences(of: pattern, with: "$1=<redacted>",
                                           options: [.regularExpression])
        }
        // `--password hunter2` / `-u someone` — the space-separated forms, long and short, for text
        // that did not come from argv (a Wine log, a pasted command). Argv itself goes through
        // `redactCommandLine`, which is fail-closed and does not rely on this list.
        out = out.replacingOccurrences(
            of: "(?i)(--(?:password|token|secret|api[-_]?key|username|user|account|code|auth))(\\s+|=)\\S+",
            with: "$1$2<redacted>", options: [.regularExpression])
        out = out.replacingOccurrences(
            of: "(?<![\\w-])(-[upkc])(\\s+|=)\\S+",
            with: "$1$2<redacted>", options: [.regularExpression])
        return out
    }
}
