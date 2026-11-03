import Foundation

/// One Mac a game asks for: a chip and how much memory.
public struct MacRequirement: Sendable, Equatable {
    public let chip: MacChip
    public let memoryGB: Int

    public init(chip: MacChip, memoryGB: Int) {
        self.chip = chip
        self.memoryGB = memoryGB
    }

    /// "M2 Pro · 16 GB memory".
    public var label: String { String(localized: "\(chip.name) · \(memoryGB) GB memory") }

    /// The weakest chip of each other tier (Ultra aside) that draws as well, and comes with enough
    /// memory: an M5 requirement is met by an M2 Pro or an M1 Max too, and "M5 or better" alone
    /// reads to their owners as "not you".
    public var alternatives: [MacChip] {
        guard let need = chip.specs?.gpuScore else { return [] }
        return MacChip.Tier.allCases.filter { $0 != chip.tier && $0 != .ultra }.compactMap { tier in
            MacChip.ladder.first {
                guard $0.tier == tier, let specs = $0.specs else { return false }
                return specs.gpuScore >= need && specs.maxMemoryGB >= memoryGB
            }
        }
    }

    /// "M5 · 24 GB memory, or an M2 Pro or M1 Max" — what the game page lists.
    public var labelWithAlternatives: String {
        let others = alternatives.map(\.name)
        guard !others.isEmpty else { return label }
        return String(localized: "\(label), or an \(others.formatted(.list(type: .or)))")
    }

    /// Whether this requirement asks for at least as much as `other`.
    public func covers(_ other: MacRequirement) -> Bool {
        (chip.atLeast(other.chip) ?? false) && memoryGB >= other.memoryGB
    }
}
