import Foundation

/// A reference to a game profile TOML on disk. Structured decoding of the full schema
/// arrives with the Phase 2 profile loader; Phase 0 discovers and displays raw profiles.
public struct ProfileRef {
    public let slug: String
    public let url: URL
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

