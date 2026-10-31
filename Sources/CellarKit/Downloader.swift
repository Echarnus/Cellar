import CellarDomain
import Foundation

/// Downloads files via curl (handles redirects, large files, and shows a live progress bar on a TTY).
public enum Downloader {
    /// Fetch `url` to `destination`. Creates parent directories as needed.
    @discardableResult
    public static func fetch(_ url: String, to destination: URL, showProgress: Bool = true) throws -> URL {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Inherit stdio (no pipes) so curl's progress bar renders live.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var args: [String] = [
            showProgress ? "--progress-bar" : "-s",
            "-L",            // follow redirects
            "--fail",        // non-zero exit on HTTP errors
        ]
        args += httpsOnly
        args += ["-o", destination.path, url]
        process.arguments = args

        do {
            try process.run()
        } catch {
            throw CellarError.ioFailure("Could not start curl: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CellarError.ioFailure("Download failed (curl exit \(process.terminationStatus)) for \(url)")
        }
        return destination
    }

    /// Fetch a URL and return its body as a String (for small API/JSON responses).
    public static func string(_ url: String) throws -> String {
        let result = Shell.run("/usr/bin/curl", ["-sL", "--fail", url])
        guard result.succeeded else {
            throw CellarError.ioFailure("Request failed for \(url): \(result.stderr)")
        }
        return result.stdout
    }

    /// Fetch a URL as JSON, optionally with an OAuth bearer token.
    ///
    /// Uses curl like the rest of this type rather than URLSession: CellarKit is synchronous by
    /// design (see skills/swift.md), and a semaphore-blocked URLSession in a CLI is a deadlock
    /// waiting to happen. `-w` appends the status code so an API error is reported as an API error
    /// instead of a JSON parse failure three frames later.
    public static func json(_ url: String, bearer: String? = nil,
                            body: [String: String]? = nil) throws -> [String: Any] {
        var args: [String] = ["-sL", "-w", "\n%{http_code}"]
        args += httpsOnly
        if body != nil { args += ["-X", "POST", "-H", "Content-Type: application/x-www-form-urlencoded"] }
        let secrets = secretConfig(bearer: bearer, form: body)
        if secrets != nil { args += ["--config", "-"] }
        args.append(url)
        let result = Shell.run("/usr/bin/curl", args, input: secrets.map { Data($0.utf8) })
        guard result.succeeded else {
            throw CellarError.ioFailure("Could not reach \(host(of: url)): \(result.stderr)")
        }
        var lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: false)
        let status = Int(lines.popLast().map(String.init) ?? "") ?? 0
        let payload = lines.joined(separator: "\n")
        guard (200..<300).contains(status) else {
            throw CellarError.ioFailure("\(host(of: url)) answered HTTP \(status). \(shortMessage(payload))")
        }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CellarError.ioFailure("\(host(of: url)) returned something that isn't JSON.")
        }
        return object
    }

    /// Download with an OAuth bearer token (GOG's content links are token-gated).
    @discardableResult
    public static func fetch(_ url: String, to destination: URL, bearer: String,
                            showProgress: Bool = true, allowResume: Bool = true) throws -> URL {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var args: [String] = [showProgress ? "--progress-bar" : "-s", "-L", "--fail", "--config", "-"]
        args += httpsOnly
        process.arguments = args
        // Resume a partial file rather than starting a 40 GB download over.
        if allowResume { process.arguments! += ["-C", "-"] }
        process.arguments! += ["-o", destination.path, url]
        // The token goes in on stdin; stdout and stderr stay inherited so the progress bar draws.
        let stdin = Pipe()
        process.standardInput = stdin
        do { try process.run() } catch {
            throw CellarError.ioFailure("Could not start curl: \(error.localizedDescription)")
        }
        try? stdin.fileHandleForWriting.write(contentsOf: Data((secretConfig(bearer: bearer, form: nil) ?? "").utf8))
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        // 33 = the server refuses range requests, so the resume can't be honoured. Start over once,
        // without the range header — retrying with it would fail identically forever.
        if process.terminationStatus == 33, allowResume {
            try? FileManager.default.removeItem(at: destination)
            return try fetch(url, to: destination, bearer: bearer,
                             showProgress: showProgress, allowResume: false)
        }
        guard process.terminationStatus == 0 else {
            throw CellarError.ioFailure("Download failed (curl exit \(process.terminationStatus)) for \(host(of: url))")
        }
        return destination
    }

    /// HTTPS only, redirects included: a redirect to plain `http://` (or `file://`, `ftp://`) is
    /// refused rather than followed, so nothing Cellar fetches — and no token it sends — can be
    /// downgraded off TLS.
    static let httpsOnly = ["--proto", "=https", "--proto-redir", "=https"]

    /// What a request has to send that is a secret, as a curl config file for `--config -`.
    ///
    /// An OAuth token or refresh token on curl's command line is readable by every process on the
    /// Mac for as long as the request runs (`ps -o args`), including the Windows programs Cellar
    /// itself starts. Read from stdin it is in curl's memory only. Nil when there is nothing secret.
    static func secretConfig(bearer: String?, form: [String: String]?) -> String? {
        var lines: [String] = []
        if let bearer { lines.append("header = \(configQuoted("Authorization: Bearer \(bearer)"))") }
        if let form { lines.append("data = \(configQuoted(formEncode(form)))") }
        return lines.isEmpty ? nil : lines.joined(separator: "\n") + "\n"
    }

    /// A value quoted for a curl config file: inside double quotes, with `\` and `"` escaped and
    /// line breaks dropped, so a value can never end its own line and start another option.
    static func configQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        return "\"" + escaped + "\""
    }

    public static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
    }

    static func host(of url: String) -> String { URL(string: url)?.host ?? url }

    /// A one-line version of an API error body, for an error message a person can read.
    static func shortMessage(_ payload: String) -> String {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        for key in ["error_description", "message", "error"] {
            if let value = object[key] as? String { return value }
        }
        return ""
    }
}
