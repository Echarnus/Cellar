import Foundation

/// Where an install stands: the phase, and how far through it when that can be measured.
public struct InstallProgress: Sendable, Equatable {
    public let phase: InstallPhase
    /// 0…1, or nil when the phase has no honest denominator.
    public let fraction: Double?

    public init(_ phase: InstallPhase, fraction: Double? = nil) {
        self.phase = phase
        self.fraction = fraction.map { min(max($0, 0), 1) }
    }
}
