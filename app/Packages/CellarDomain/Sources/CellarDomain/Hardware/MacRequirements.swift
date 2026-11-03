import Foundation

/// The Mac a game needs, and the Mac it is best on — from the publisher's own PC requirements.
///
/// Publishers name PC graphics cards; players own Macs. The mapping is one rule, the same for every
/// game (`derive`): the card's graphics score, raised by what running a Windows game through the
/// translation layer costs (`overhead`), gives the weakest Apple chip that draws that well; the
/// PC's memory plus the card's video memory gives the unified memory, because a Mac shares one pool
/// between the two. A profile may ask for more than the rule gives, never less, and says why
/// (`reason`). `MacRequirementsTests` holds every shipped profile to it.
///
/// It is an estimate from the publisher's numbers, not a test, and every sentence it produces says
/// so. See `docs/MAC-REQUIREMENTS.md`.
public struct MacRequirements: Sendable, Equatable {
    /// The Mac the game starts and plays on, at low settings.
    public let minimum: MacRequirement
    /// The Mac for a decent experience: the publisher's recommended PC, translated.
    public let recommended: MacRequirement
    /// Why a profile asks for more than the rule gives (a game heavy on the processor, a port
    /// known to run worse than its numbers). Nil when it asks for exactly what the rule gives.
    public let reason: String?
    /// Where the PC requirements were read, and when.
    public let source: String?

    public init(minimum: MacRequirement, recommended: MacRequirement, reason: String? = nil, source: String? = nil) {
        self.minimum = minimum
        self.recommended = recommended
        self.reason = reason
        self.source = source
    }

    // MARK: - The rule

    /// What translating a Windows game costs in graphics performance: Wine, then D3DMetal or
    /// DXVK → MoltenVK, then Rosetta for the game's own code. Measured ports and CrossOver
    /// comparisons put it around a quarter to a third of the frame rate; 1.3 is the middle.
    public static let overhead = 1.3

    /// The unified memory sizes Apple sells, in GB.
    public static let memorySizes = [8, 16, 24, 32, 36, 48, 64, 96, 128, 192, 256, 512]

    /// The Mac that matches a PC with `card` and `memoryGB` of memory, under Cellar's overhead:
    /// the weakest known chip whose graphics score covers the card's, that Apple sells with
    /// enough memory. Nil when no Mac does.
    public static func derive(card: PCGraphicsCard, memoryGB: Int) -> MacRequirement? {
        let needScore = Int((Double(card.score) * overhead).rounded(.up))
        let needMemory = Double(memoryGB) + card.videoMemoryGB
        guard let memory = memorySizes.first(where: { Double($0) >= needMemory }) else { return nil }
        guard let chip = MacChip.ladder.first(where: {
            guard let specs = $0.specs else { return false }
            return specs.gpuScore >= needScore && specs.maxMemoryGB >= memory
        }) else { return nil }
        return MacRequirement(chip: chip, memoryGB: memory)
    }

    // MARK: - Reading a profile

    /// The profile keys, in the `[mac]` section. Flat names, because `ProfileStore.fields` ignores
    /// sections (skills/profiles.md).
    public enum Key {
        public static let pcGPUMinimum = "pc_gpu_minimum"
        public static let pcMemoryMinimum = "pc_memory_minimum"
        public static let pcGPURecommended = "pc_gpu_recommended"
        public static let pcMemoryRecommended = "pc_memory_recommended"
        public static let macMinimum = "mac_minimum"
        public static let macMemoryMinimum = "mac_memory_minimum"
        public static let macRecommended = "mac_recommended"
        public static let macMemoryRecommended = "mac_memory_recommended"
        public static let reason = "mac_reason"
        public static let source = "pc_requirements_source"
    }

    /// The requirements a profile states. Nil when it states none, or names a chip Cellar can't
    /// read — the profile lint says which.
    public init?(fields: [String: String]) {
        guard let minChip = fields[Key.macMinimum].flatMap({ MacChip($0) }),
              let minMemory = fields[Key.macMemoryMinimum].flatMap({ Int($0) }),
              let recChip = fields[Key.macRecommended].flatMap({ MacChip($0) }),
              let recMemory = fields[Key.macMemoryRecommended].flatMap({ Int($0) }) else { return nil }
        self.init(minimum: MacRequirement(chip: minChip, memoryGB: minMemory),
                  recommended: MacRequirement(chip: recChip, memoryGB: recMemory),
                  reason: fields[Key.reason].flatMap { $0.isEmpty ? nil : $0 },
                  source: fields[Key.source].flatMap { $0.isEmpty ? nil : $0 })
    }

    // MARK: - What the player reads

    /// The tag on the game page: the Mac for a decent experience.
    public var tag: String { String(localized: "Best on \(recommended.chip.name) or better") }

    /// The facts list: what the game needs, what it is best on, and how this Mac compares.
    public func rows(thisMac: ThisMac?) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [
            (String(localized: "Minimum"), minimum.labelWithAlternatives),
            (String(localized: "Recommended"), recommended.labelWithAlternatives),
        ]
        if let thisMac, let sentence = verdict(for: thisMac).sentence(thisMac: thisMac) {
            rows.append((String(localized: "This Mac"), sentence))
        }
        return rows
    }

    /// Said under the tag, in its tooltip: what the two Macs are, and that it is not a test.
    public var explanation: String {
        String(localized: "Estimated from the publisher's PC requirements, not tested: \(minimum.label) to start and play at low settings, \(recommended.label) for a smooth game at good settings.")
    }

    /// The player's Mac, read once: its chip and memory.
    public struct ThisMac: Sendable, Equatable {
        public let chip: MacChip?
        public let memoryGB: Int

        public init(chip: MacChip?, memoryGB: Int) {
            self.chip = chip
            self.memoryGB = memoryGB
        }
    }

    public enum Verdict: Sendable, Equatable {
        case recommended
        case minimum
        case belowMinimum
        /// The chip is one Cellar can't place (a newer one than it knows), or not Apple silicon.
        case unknown

        /// One plain sentence about this Mac. Nil when there is nothing honest to say.
        public func sentence(thisMac: ThisMac) -> String? {
            guard let chip = thisMac.chip else { return nil }
            switch self {
            case .recommended:
                return String(localized: "\(chip.name), \(thisMac.memoryGB) GB: should run it well.")
            case .minimum:
                return String(localized: "\(chip.name), \(thisMac.memoryGB) GB: enough to play. Expect to lower the graphics settings.")
            case .belowMinimum:
                return String(localized: "\(chip.name), \(thisMac.memoryGB) GB: below what this game needs. It may not start, or run poorly.")
            case .unknown:
                return nil
            }
        }
    }

    public func verdict(for mac: ThisMac) -> Verdict {
        guard let chip = mac.chip else { return .unknown }
        func meets(_ requirement: MacRequirement) -> Bool? {
            guard let enough = chip.atLeast(requirement.chip) else { return nil }
            return enough && mac.memoryGB >= requirement.memoryGB
        }
        switch (meets(recommended), meets(minimum)) {
        case (true?, _):  return .recommended
        case (_, true?):  return .minimum
        case (_, false?): return .belowMinimum
        default:          return .unknown
        }
    }

    /// Whether the recommended Mac asks for at least as much as the minimum one.
    public var isOrdered: Bool { recommended.covers(minimum) }
}
