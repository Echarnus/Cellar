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
}
