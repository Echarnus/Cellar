import CellarDomain
import Foundation

/// Who Cellar is built on. One list, shown verbatim by the app's About panel and Settings › About,
/// so the two can never disagree about whom to thank.
///
/// Wine is first on purpose: everything Cellar does happens inside Wine. Cellar adds a runner
/// catalogue, bottles, profiles and a launcher on top — the Win32 implementation is all theirs.
public struct Credit: Sendable, Equatable {
    public let name: String
    /// One plain sentence: what the project does for Cellar.
    public let role: String
    public let license: String
    public let url: URL
    /// Where the source lives, when that is a different place from the project's front door.
    public let sourceURL: URL?

    public init(name: String, role: String, license: String, url: String, sourceURL: String? = nil) {
        self.name = name
        self.role = role
        self.license = license
        self.url = URL(string: url)!
        self.sourceURL = sourceURL.map { URL(string: $0)! }
    }
}
