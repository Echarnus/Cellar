import Foundation

/// What a program Cellar starts may inherit from the environment that started Cellar (#238).
///
/// Wine, the store client, the game and DepotDownloader all run code Cellar didn't write, and
/// whatever is in their environment they can read, log or send on. Started from the app or a
/// game's Dock icon, that environment is launchd's and holds nothing private. Started from a
/// shell (a developer's terminal, or an agent running `cellar verify`), it can hold API tokens,
/// OAuth scopes, cloud keys, an SSH agent socket. So the inherited part is an **allow-list**: the
/// session basics a macOS process expects, and nothing else. Cellar's own variables are added on
/// top by each caller, as before.
///
/// Not a bare environment: Planet Coaster 2 exits silently about 4 s after launch with one (the
/// reason `WineRunner` inherits at all), so the basics (`TMPDIR`, `USER`, the locale,
/// `__CF_USER_TEXT_ENCODING`…) stay.
public enum ChildEnvironment {
    /// Variables passed through by exact name.
    static let names: Set<String> = [
        "HOME", "USER", "LOGNAME", "SHELL", "PATH", "TMPDIR",
        "LANG", "LANGUAGE", "TZ", "TERM", "DISPLAY", "COMMAND_MODE",
        "__CF_USER_TEXT_ENCODING", "__CFBundleIdentifier", "SECURITYSESSIONID",
    ]

    /// Variables passed through by prefix: the locale categories, macOS's per-process XPC
    /// bookkeeping, and the player's own SDL hints (a wheel's force-feedback gain, which
    /// `CellarSDL.applyStrength` deliberately leaves alone when set).
    static let prefixes = ["LC_", "XPC_", "SDL_"]

    /// The part of `environment` a child may inherit. `alsoAllowing` adds prefixes one caller
    /// needs (DepotDownloader's `DOTNET_`).
    public static func inherited(from environment: [String: String] = ProcessInfo.processInfo.environment,
                                 alsoAllowing extra: [String] = []) -> [String: String] {
        environment.filter { isAllowed($0.key, extraPrefixes: extra) }
    }

    static func isAllowed(_ key: String, extraPrefixes: [String] = []) -> Bool {
        names.contains(key) || (prefixes + extraPrefixes).contains { key.hasPrefix($0) }
    }
}
