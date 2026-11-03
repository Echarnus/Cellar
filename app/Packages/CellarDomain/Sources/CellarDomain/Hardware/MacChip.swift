import Foundation

/// An Apple silicon chip, as a player names it: "M2 Pro".
///
/// A game's Mac requirement is said as one of these, and the player's own Mac is read as one, so
/// the two can be compared. What decides a game's frame rate on a Mac is almost always the
/// graphics, so chips are ranked by their GPU (`gpuScore`), not by their name: an M1 Max draws
/// more than an M4, and "M4 or better" must not tell an M1 Max owner their Mac is too slow.
///
/// See `docs/MAC-REQUIREMENTS.md` for where the numbers come from.
public struct MacChip: Sendable, Hashable, CustomStringConvertible {
    public enum Tier: Int, Sendable, Comparable, CaseIterable {
        case base, pro, max, ultra

        public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }

        var suffix: String {
            switch self {
            case .base:  return ""
            case .pro:   return " Pro"
            case .max:   return " Max"
            case .ultra: return " Ultra"
            }
        }
    }

    /// 1 for M1, 4 for M4.
    public let generation: Int
    public let tier: Tier

    public init(generation: Int, tier: Tier) {
        self.generation = generation
        self.tier = tier
    }

    /// "M2 Pro".
    public var name: String { "M\(generation)\(tier.suffix)" }
    public var description: String { name }

    /// Reads "M2 Pro", "m2 pro" or the brand string a Mac reports ("Apple M2 Pro"). Nil for
    /// anything else, an Intel Mac included.
    public init?(_ text: String) {
        let words = text.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        guard let index = words.firstIndex(where: { $0.hasPrefix("m") && Int($0.dropFirst()) != nil }),
              let generation = Int(words[index].dropFirst()), generation > 0 else { return nil }
        let rest = words.dropFirst(index + 1).first
        let tier: Tier
        switch rest {
        case nil:      tier = .base
        case "pro":    tier = .pro
        case "max":    tier = .max
        case "ultra":  tier = .ultra
        default:       return nil
        }
        self.init(generation: generation, tier: tier)
    }

    /// What Cellar knows about a chip it has numbers for.
    public struct Specs: Sendable {
        /// Graphics performance, relative to the M1's 8-core GPU = 100. For the chip's top GPU
        /// configuration — the one its name stands for in a requirement.
        public let gpuScore: Int
        /// The most unified memory Apple sells this chip with, in GB.
        public let maxMemoryGB: Int
    }

    /// Every chip Cellar has numbers for. Relative GPU performance from public benchmarks
    /// (Notebookcheck's GPU comparisons, Apple's own generation-over-generation figures); the
    /// memory ceilings are Apple's tech specs. A newer chip than these is still compared — see
    /// `atLeast(_:)` — it just isn't one a requirement can name until it is added here.
    public static let known: [MacChip: Specs] = [
        MacChip(generation: 1, tier: .base):  Specs(gpuScore: 100, maxMemoryGB: 16),
        MacChip(generation: 1, tier: .pro):   Specs(gpuScore: 200, maxMemoryGB: 32),
        MacChip(generation: 1, tier: .max):   Specs(gpuScore: 380, maxMemoryGB: 64),
        MacChip(generation: 1, tier: .ultra): Specs(gpuScore: 700, maxMemoryGB: 128),
        MacChip(generation: 2, tier: .base):  Specs(gpuScore: 135, maxMemoryGB: 24),
        MacChip(generation: 2, tier: .pro):   Specs(gpuScore: 250, maxMemoryGB: 32),
        MacChip(generation: 2, tier: .max):   Specs(gpuScore: 470, maxMemoryGB: 96),
        MacChip(generation: 2, tier: .ultra): Specs(gpuScore: 880, maxMemoryGB: 192),
        MacChip(generation: 3, tier: .base):  Specs(gpuScore: 165, maxMemoryGB: 24),
        MacChip(generation: 3, tier: .pro):   Specs(gpuScore: 260, maxMemoryGB: 36),
        MacChip(generation: 3, tier: .max):   Specs(gpuScore: 560, maxMemoryGB: 128),
        MacChip(generation: 3, tier: .ultra): Specs(gpuScore: 1050, maxMemoryGB: 512),
        MacChip(generation: 4, tier: .base):  Specs(gpuScore: 180, maxMemoryGB: 32),
        MacChip(generation: 4, tier: .pro):   Specs(gpuScore: 340, maxMemoryGB: 64),
        MacChip(generation: 4, tier: .max):   Specs(gpuScore: 680, maxMemoryGB: 128),
        MacChip(generation: 5, tier: .base):  Specs(gpuScore: 240, maxMemoryGB: 32),
    ]

    public var specs: Specs? { Self.known[self] }

    /// The known chips, weakest graphics first.
    public static let ladder: [MacChip] = known.keys.sorted {
        (known[$0]!.gpuScore, $0.generation) < (known[$1]!.gpuScore, $1.generation)
    }

    /// Whether this chip draws at least as well as `required`.
    ///
    /// Two known chips compare by their numbers. A chip Cellar has no numbers for yet (a newer
    /// generation) counts as at least as good as every known chip of the same tier or below from
    /// its own generation or earlier — Apple has never shipped a successor that draws less than the
    /// chip it replaced. Nil when even that can't say: an unknown chip against a requirement
    /// above everything it can be vouched for by.
    public func atLeast(_ required: MacChip) -> Bool? {
        guard let need = required.specs?.gpuScore else { return nil }
        if let mine = specs?.gpuScore { return mine >= need }
        let vouchedFor = Self.known.filter { $0.key.generation <= generation && $0.key.tier <= tier }
            .map { $0.value.gpuScore }.max()
        guard let floor = vouchedFor, floor >= need else { return nil }
        return true
    }
}
