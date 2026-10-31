import CellarDomain
import Foundation

/// "Can the game get online from inside its bottle?" — asked of the same Windows network stack the
/// game uses, and of the Mac beside it, so the answer can say *whose* problem a failure is.
///
/// A game's online features (Planet Coaster 2's Frontier Workshop, a store's news feed…) go through
/// Windows' WinHTTP → Schannel → crypt32, which under Wine are `winhttp.dll`, `secur32` over the
/// runner's GnuTLS, and macOS's trust store. Any of those can fail where the Mac's own networking
/// works, and the game only ever says "network error". So the check runs a small JScript inside the
/// bottle (`cscript` + `WinHttp.WinHttpRequest`, both part of Wine) against each address, does the
/// same request from the Mac with `URLSession`, and compares:
///
/// - both fail → the Mac itself can't reach it: the network, a firewall, or the service is down;
/// - only the bottle fails → Cellar's layer is in the way, and the reason says which part of it;
/// - neither fails → the path is open, so a game still showing an error is down to the service or
///   the player's account (Frontier's Workshop needs a linked Frontier account).
public enum NetworkCheck {

    /// What one request came back with. Any HTTP status counts as reached: a 403 or 404 still proves
    /// name lookup, connection and TLS all worked, which is everything this check is about.
    public enum Outcome: Equatable, Sendable {
        case reached(status: Int)
        case nameNotResolved
        case cannotConnect
        case timedOut
        case secureConnectionFailed
        case certificateRejected
        case other(code: Int)

        public var reached: Bool { if case .reached = self { return true } else { return false } }

        /// A plain sentence for the player. No error numbers: the code goes in the log.
        public var sentence: String {
            switch self {
            case .reached(let status):    return "reached (HTTP \(status))"
            case .nameNotResolved:        return "the name could not be looked up (DNS)"
            case .cannotConnect:          return "no connection could be made"
            case .timedOut:               return "it did not answer in time"
            case .secureConnectionFailed: return "the secure (TLS) connection failed"
            case .certificateRejected:    return "its certificate was not trusted"
            case .other(let code):        return "it failed (error \(code))"
            }
        }

        /// WinHTTP's `ERROR_WINHTTP_*` codes — the low 16 bits of the HRESULT a script sees.
        public init(winHTTPError code: Int) {
            switch code {
            case 12007:                                        self = .nameNotResolved
            case 12029, 12030, 12031, 12152:                   self = .cannotConnect
            case 12002:                                        self = .timedOut
            case 12157, 12175:                                 self = .secureConnectionFailed
            case 12037, 12038, 12044, 12045, 12057, 12169, 12179: self = .certificateRejected
            default:                                           self = .other(code: code)
            }
        }

        public init(urlError: URLError) {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed:
                self = .nameNotResolved
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                self = .cannotConnect
            case .timedOut:
                self = .timedOut
            case .secureConnectionFailed, .clientCertificateRejected, .clientCertificateRequired:
                self = .secureConnectionFailed
            case .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                self = .certificateRejected
            default:
                self = .other(code: urlError.errorCode)
            }
        }
    }

    public struct Result: Equatable, Sendable {
        public let url: String
        public let mac: Outcome
        public let bottle: Outcome

        public init(url: String, mac: Outcome, bottle: Outcome) {
            self.url = url
            self.mac = mac
            self.bottle = bottle
        }

        public var host: String { URL(string: url)?.host ?? url }

        /// Only the bottle fails: the one case that is Cellar's to fix.
        public var layerIsInTheWay: Bool { mac.reached && !bottle.reached }
    }

    /// The addresses a store's games need whatever the game: the store's own services.
    public static func storeURLs(_ store: GameStore) -> [String] {
        switch store {
        case .steam:     return ["https://api.steampowered.com/", "https://steamcommunity.com/"]
        case .battlenet: return ["https://us.battle.net/"]
        case .gog:       return ["https://api.gog.com/"]
        }
    }

    /// The profile's `network_check` (space-separated `https://` addresses, scalar so all three
    /// profile parsers read it the same way), after the store's own. Duplicates dropped, order kept.
    public static func urls(store: GameStore, profileValue: String?) -> [String] {
        let fromProfile = (profileValue ?? "")
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init)
            .filter { $0.hasPrefix("https://") || $0.hasPrefix("http://") }
        var seen = Set<String>()
        return (storeURLs(store) + fromProfile).filter { seen.insert($0).inserted }
    }

    /// The probe run inside the bottle. JScript, because Wine ships `cscript` and `jscript.dll`, and
    /// `WinHttp.WinHttpRequest` is the same `winhttp.dll` a game's own requests go through.
    /// Arguments: the output file, then one URL each. Writes `url<TAB>ok <status>` or
    /// `url<TAB>error <code>` per line. Results go to a file, not `WScript.Echo`: under Wine's
    /// `cscript //B` an echo can be swallowed, and a file is read back the same way every time.
    static let probeScript = """
    var fso = new ActiveXObject("Scripting.FileSystemObject");
    var args = WScript.Arguments;
    var out = fso.CreateTextFile(args.Item(0), true);
    for (var i = 1; i < args.Count(); i++) {
        var url = args.Item(i), line;
        try {
            var r = new ActiveXObject("WinHttp.WinHttpRequest.5.1");
            r.SetTimeouts(10000, 10000, 10000, 15000);
            r.Open("GET", url, false);
            r.Send();
            line = "ok " + r.Status;
        } catch (e) {
            line = "error " + (e.number & 0xFFFF);
        }
        out.WriteLine(url + "\\t" + line);
    }
    out.Close();
    """

    /// Read the probe's output back. A URL with no line (the script died before it) is left out, so
    /// the caller reports it as not checked rather than inventing an outcome.
    public static func parseProbeOutput(_ text: String) -> [String: Outcome] {
        var outcomes: [String: Outcome] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let parts = rawLine.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let words = parts[1].split(separator: " ").map(String.init)
            guard words.count == 2, let number = Int(words[1]) else { continue }
            switch words[0] {
            case "ok":    outcomes[parts[0]] = .reached(status: number)
            case "error": outcomes[parts[0]] = Outcome(winHTTPError: number)
            default:      continue
            }
        }
        return outcomes
    }

    /// One sentence on what the results add up to — the answer the player came for.
    public static func verdict(_ results: [Result]) -> String {
        if let blocked = results.first(where: \.layerIsInTheWay) {
            return "Your Mac reaches \(blocked.host), but the game's bottle can't: \(blocked.bottle.sentence). "
                + "That is Cellar's to fix — please attach the report from: cellar logs report"
        }
        if let down = results.first(where: { !$0.mac.reached }) {
            return "\(down.host) can't be reached from this Mac either (\(down.mac.sentence)). "
                + "Check your internet connection or firewall; the service itself may be down."
        }
        return "The game's bottle reaches every service it was checked against. If an online feature "
            + "still says \"network error\", the service or your account is the place to look — "
            + "not the layer."
    }

    /// Run the check: every URL from the Mac, then all of them at once from inside the bottle.
    public static func run(_ wine: WineRunner, urls: [String]) -> [Result] {
        let bottle = probeBottle(wine, urls: urls)
        return urls.map { url in
            Result(url: url, mac: probeMac(url), bottle: bottle[url] ?? .other(code: -1))
        }
    }

    static func probeBottle(_ wine: WineRunner, urls: [String]) -> [String: Outcome] {
        let temp = wine.prefix.appendingPathComponent("drive_c/windows/temp", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let script = temp.appendingPathComponent("cellar-network-check.js")
        let output = temp.appendingPathComponent("cellar-network-check.txt")
        try? FileManager.default.removeItem(at: output)
        guard (try? probeScript.write(to: script, atomically: true, encoding: .utf8)) != nil else { return [:] }
        defer {
            try? FileManager.default.removeItem(at: script)
            try? FileManager.default.removeItem(at: output)
        }
        // Wine's own complaints about TLS and certificates go to the log, so a failure that names
        // no reason here still leaves one behind for `cellar logs report`.
        let result = wine.run(
            ["cscript", "//nologo", "//B", #"C:\windows\temp\cellar-network-check.js"#,
             #"C:\windows\temp\cellar-network-check.txt"#] + urls,
            extraEnv: ["WINEDEBUG": "err+winhttp,err+secur32,err+crypt,err+chain,fixme-all"])
        let complaints = result.stderr.split(whereSeparator: \.isNewline)
            .filter { $0.contains("err:") }.prefix(20)
        for line in complaints { CellarLog.debug(.launch, String(line), subject: "network-check") }
        let text = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        return parseProbeOutput(text)
    }

    static func probeMac(_ url: String) -> Outcome {
        guard let target = URL(string: url) else { return .other(code: -1) }
        var request = URLRequest(url: target, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        let done = DispatchSemaphore(value: 0)
        let answer = Answer()
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            let outcome: Outcome
            if let http = response as? HTTPURLResponse {
                outcome = .reached(status: http.statusCode)
            } else if let error = error as? URLError {
                outcome = Outcome(urlError: error)
            } else if let error {
                outcome = .other(code: (error as NSError).code)
            } else {
                outcome = .other(code: -1)
            }
            answer.lock.withLock { answer.outcome = outcome }
            done.signal()
        }
        task.resume()
        if done.wait(timeout: .now() + 20) == .timedOut { task.cancel() }
        return answer.lock.withLock { answer.outcome }
    }

    /// The URLSession callback's answer, handed back across threads.
    private final class Answer: @unchecked Sendable {
        let lock = NSLock()
        var outcome = Outcome.timedOut
    }
}
