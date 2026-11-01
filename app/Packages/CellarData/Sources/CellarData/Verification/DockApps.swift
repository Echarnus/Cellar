import Foundation

/// What is in the Dock while a game runs, for `cellar verify`'s `dock` check (#208).
///
/// macOS gives a Dock icon to every app whose type is `Foreground`; `lsappinfo list` names each
/// running app with its type, bundle and executable. That is the list the player sees, so it is
/// the one judged: "wine", "wine64" or Steam there is the bug that kept coming back (PR #201,
/// #220), and the game has to be there under its own name, from the app Cellar made for it.
public enum DockApps {
    public struct App: Equatable, Sendable {
        public var name: String
        public var bundlePath: String?
        public var executablePath: String?
        public var pid: Int32?
        public var type: String?

        public var isInDock: Bool { type?.lowercased() == "foreground" }
    }

    /// Every app `lsappinfo list` printed, in order.
    public static func apps(inLsappinfo text: String) -> [App] {
        var apps: [App] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // ` 12) "Planet Coaster 2" ASN:0x0-0x1a01a:`
            if let paren = line.firstIndex(of: ")"), Int(line[..<paren]) != nil,
               let name = quoted(after: line.index(after: paren), in: line) {
                apps.append(App(name: name))
                continue
            }
            guard !apps.isEmpty else { continue }
            if let path = value(of: "bundle path=", in: line) { apps[apps.count - 1].bundlePath = path }
            if let path = value(of: "executable path=", in: line) { apps[apps.count - 1].executablePath = path }
            if line.hasPrefix("pid = ") {
                let number = line.dropFirst(6).prefix { $0.isNumber }
                apps[apps.count - 1].pid = Int32(number)
                if let type = value(of: "type=", in: line) { apps[apps.count - 1].type = type }
            }
        }
        return apps
    }

    /// The Dock as it is now. Empty if `lsappinfo` isn't there or printed nothing.
    public static func current() -> [App] {
        apps(inLsappinfo: Shell.run("/usr/bin/lsappinfo", ["list"]).stdout)
    }

    /// Names that must never show in the Dock: Wine's own loader, or the store client.
    static let forbiddenNames: Set<String> = ["wine", "wine64", "wine64-preloader", "wine-preloader",
                                              "steam", "steam.exe", "steamwebhelper", "steamwebhelper.exe"]

    /// The Dock icons that shouldn't be there while a game runs: Wine or Steam by name, or anything
    /// started from the runner that isn't the game's own app (`gameBundle`).
    public static func intruders(in apps: [App], runnerRoot: String?, gameBundle: String) -> [App] {
        let bundle = normalized(gameBundle)
        return apps.filter { app in
            guard app.isInDock else { return false }
            if let bundlePath = app.bundlePath, normalized(bundlePath) == bundle { return false }
            let fromRunner = runnerRoot.flatMap { root in
                app.executablePath.map { normalized($0).hasPrefix(normalized(root) + "/") }
            } ?? false
            // The player's own Mac Steam (`/Applications/Steam.app`) is theirs, not a leak.
            if forbiddenNames.contains(app.name.lowercased()), app.bundlePath == nil || fromRunner { return true }
            return fromRunner
        }
    }

    /// The game's own Dock icon: in the Dock, from the game's app, under its name.
    public static func game(in apps: [App], gameBundle: String, name: String) -> App? {
        apps.first { $0.isInDock && $0.bundlePath.map(normalized) == normalized(gameBundle) && $0.name == name }
    }

    private static func normalized(_ path: String) -> String {
        var path = path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    private static func quoted(after start: String.Index, in line: String) -> String? {
        guard let open = line[start...].firstIndex(of: "\"") else { return nil }
        let rest = line[line.index(after: open)...]
        guard let close = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<close])
    }

    private static func value(of key: String, in line: String) -> String? {
        guard let range = line.range(of: key) else { return nil }
        let rest = line[range.upperBound...]
        if rest.hasPrefix("\"") { return quoted(after: rest.startIndex, in: line) }
        let word = rest.prefix { !$0.isWhitespace }
        // `bundle path=[ NULL ]` for an app with no bundle.
        return word.isEmpty || word.hasPrefix("[") ? nil : String(word)
    }
}
