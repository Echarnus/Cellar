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
