import CellarDomain
import Foundation

/// A reference to a game profile TOML on disk. Structured decoding of the full schema
/// arrives with the Phase 2 profile loader; Phase 0 discovers and displays raw profiles.
public struct ProfileRef {
    public let slug: String
    public let url: URL

    public init(slug: String, url: URL) {
        self.slug = slug
        self.url = url
    }
}

public enum ProfileStore {
    /// All discoverable profiles, de-duplicated by slug across the search paths
    /// (user/registry profiles win over repo-bundled ones).
    public static func all() -> [ProfileRef] {
        let fm = FileManager.default
        var seen = Set<String>()
        var result: [ProfileRef] = []
        for dir in Paths.profileSearchPaths {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in entries where url.pathExtension == "toml" {
                let slug = url.deletingPathExtension().lastPathComponent
                if seen.insert(slug).inserted {
                    result.append(ProfileRef(slug: slug, url: url))
                }
            }
        }
        return result.sorted { $0.slug < $1.slug }
    }

    public static func find(_ slug: String) -> ProfileRef? {
        all().first { $0.slug == slug }
    }

    /// The `[env]` section of a profile: environment variables applied to the game (and to the
    /// Steam client that spawns it). Values are strings; keys are used verbatim.
    public static func env(_ ref: ProfileRef) -> [String: String] { env(at: ref.url) }

    /// The `[env]` section of any Cellar TOML file — a profile, or a bottle's `bottle.toml`.
    public static func env(at url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var dict: [String: String] = [:]
        var inEnv = false
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inEnv = (line == "[env]"); continue }
            guard inEnv, !line.hasPrefix("#"), line.contains("=") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            var value = parts[1]
            if let hash = value.range(of: " #") { value = String(value[..<hash.lowerBound]) }
            let key = parts[0]
            guard isAllowedEnvKey(key) else {
                CellarLog.warn(.app, "Ignored \(key) in \(url.lastPathComponent): a game file may not set "
                    + "variables that change which code macOS or Wine loads.")
                continue
            }
            dict[key] = value.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return dict
    }

    /// Variables an `[env]` block may never set, because they decide *which code runs* rather than
    /// how a game behaves: the dynamic loader's injection and search paths (`DYLD_INSERT_LIBRARIES`
    /// would load any dylib into Wine, which is not hardened), the Wine binaries and prefix Cellar
    /// chose, and the shell basics. A profile arrives from the signed game database, so this is
    /// defence in depth: a compromised key or a bad merge still cannot turn a profile into code
    /// execution on the Mac. Cellar sets these itself in `WineRunner.environment`.
    static let deniedEnvPrefixes = ["DYLD_", "LD_", "WINEDLLPATH", "CELLAR_"]
    static let deniedEnvKeys: Set<String> = [
        "WINELOADER", "WINESERVER", "WINEPREFIX", "WINEARCH",
        "PATH", "HOME", "TMPDIR", "SHELL", "USER", "LOGNAME",
        "GST_PLUGIN_PATH", "D3DMETAL_RUNTIME_DIR", "DXMT_RUNTIME_DIR",
    ]

    /// Whether an `[env]` block may set `key`. Case-sensitive, like the environment itself.
    public static func isAllowedEnvKey(_ key: String) -> Bool {
        guard !key.isEmpty, !deniedEnvKeys.contains(key) else { return false }
        return !deniedEnvPrefixes.contains { key.hasPrefix($0) }
    }

    /// Flat scan of a profile's scalar `key = "value"` pairs (section headers ignored, last wins).
    /// Enough for Phase 1 launch needs; the full typed schema decoder arrives in Phase 2.
    public static func fields(_ ref: ProfileRef) -> [String: String] {
        guard let text = try? String(contentsOf: ref.url, encoding: .utf8) else { return [:] }
        var dict: [String: String] = [:]
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), !line.hasPrefix("["), line.contains("=") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            // strip an inline comment then surrounding quotes
            var value = parts[1]
            if let hash = value.range(of: " #") { value = String(value[..<hash.lowerBound]) }
            dict[parts[0]] = value.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return dict
    }
}

