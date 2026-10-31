import CellarDomain
import Foundation

/// Describes a downloadable Wine runner family (where to get it, how it's laid out).
public struct RunnerSpec: Sendable {
    public let id: String            // Cellar id, e.g. "sikarugir"
    public let displayName: String
    public let artifacts: [RunnerArtifact]
    public let wineBinaryName: String // "wine" (wow64 builds) or "wine64" (GPTK)
    public let hasD3DMetal: Bool
    public let license: String
    public let deprecated: String?    // why not to pick it, if applicable
    /// Declared architecture of the runner's binaries. Defaults to `.x86_64` so a new entry has to
    /// opt in to claiming it is native; `RunnerInstall.measuredArchitectures` checks the claim.
    public var architecture: RunnerArchitecture = .x86_64
    /// The in-layer x86 emulator an ARM64EC runner uses (e.g. "FEX"), when it has one.
    /// `nil` on x86_64 runners — there the translator is Rosetta 2, outside our layer.
    public var emulator: String? = nil
}
