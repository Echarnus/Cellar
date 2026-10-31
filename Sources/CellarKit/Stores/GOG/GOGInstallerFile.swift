import CellarDomain
import Foundation

/// One downloadable installer file (GOG splits large games into a setup .exe plus .bin parts).
public struct GOGInstallerFile: Sendable {
    public let name: String
    public let sizeBytes: Int64
    /// The token-gated indirection URL; resolve it to a real content URL right before downloading.
    public let downlinkURL: String
}
