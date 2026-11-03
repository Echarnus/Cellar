import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The Mac each game needs and the Mac it is best on (#298).
///
/// Two halves. The rule: how a publisher's PC card becomes an Apple chip, and how a player's Mac is
/// compared with it — so "M5 or better" never tells an M1 Max owner their Mac is too slow. And the
/// database: every shipped profile carries both Macs, names cards Cellar knows, and states exactly
/// what the rule gives (or more, with a reason). That second half is the gate: a new profile without
/// its `[mac]` section fails here, so no game can land without one. See docs/MAC-REQUIREMENTS.md.
@Suite(.serialized)
struct MacRequirementsTests {

    static let staged: Bool = { _ = ProfileDatabaseTests.slugs; return true }()

    static func fields(_ slug: String) throws -> [String: String] {
        _ = staged
        return ProfileStore.fields(try #require(ProfileStore.find(slug), "'\(slug)' is not in profiles/"))
    }

    static let m1 = MacChip(generation: 1, tier: .base)
    static let m1Pro = MacChip(generation: 1, tier: .pro)
    static let m1Max = MacChip(generation: 1, tier: .max)
    static let m2Pro = MacChip(generation: 2, tier: .pro)
    static let m3Max = MacChip(generation: 3, tier: .max)
    static let m4 = MacChip(generation: 4, tier: .base)
    static let m4Max = MacChip(generation: 4, tier: .max)
    static let m5 = MacChip(generation: 5, tier: .base)

    // MARK: - Chips

    @Test("A chip is read the way a player writes it and the way a Mac reports it")
    func chipParsing() {
        #expect(MacChip("M2 Pro") == Self.m2Pro)
        #expect(MacChip("Apple M2 Pro") == Self.m2Pro, "machdep.cpu.brand_string on an M2 Pro")
        #expect(MacChip("Apple M1") == Self.m1)
        #expect(MacChip("apple m4 max") == Self.m4Max)
        #expect(MacChip("Apple M3 Ultra") == MacChip(generation: 3, tier: .ultra))
        #expect(MacChip("Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz") == nil, "an Intel Mac has no chip to compare")
        #expect(MacChip("") == nil)
        #expect(MacChip("M2 Turbo") == nil, "a tier Apple never sold is not quietly read as the base chip")
        #expect(Self.m2Pro.name == "M2 Pro")
        #expect(Self.m5.name == "M5")
    }

    @Test("Chips are ranked by their graphics, not their name")
    func ranking() {
        #expect(Self.m1Max.atLeast(Self.m4) == true, "an M1 Max draws more than an M4")
        #expect(Self.m4.atLeast(Self.m1Max) == false)
        #expect(Self.m2Pro.atLeast(Self.m5) == true, "an M2 Pro is enough where an M5 is asked for")
        #expect(Self.m1.atLeast(Self.m1) == true)
        // The ladder runs from the weakest graphics to the strongest, with no gaps in what it knows.
        let scores = MacChip.ladder.compactMap { $0.specs?.gpuScore }
        #expect(scores == scores.sorted())
        #expect(MacChip.ladder.first == Self.m1)
    }

    @Test("A chip newer than Cellar knows is vouched for by the chips it replaced, and only by them")
    func unknownChips() {
        let m6Pro = MacChip(generation: 6, tier: .pro)
        #expect(m6Pro.specs == nil)
        #expect(m6Pro.atLeast(MacChip(generation: 4, tier: .pro)) == true)
        #expect(m6Pro.atLeast(Self.m1Max) == true, "an M4 Pro already covers an M1 Max")
        #expect(MacChip(generation: 6, tier: .base).atLeast(Self.m4Max) == nil,
                "nothing vouches for a base chip against a Max: Cellar says nothing rather than guess")
        #expect(Self.m4.atLeast(m6Pro) == nil, "a requirement Cellar has no numbers for can't be met or missed")
    }

    // MARK: - The rule

    @Test("A PC card becomes the weakest chip that covers it after the translation overhead")
    func derivation() throws {
        let gtx1060 = try #require(PCGraphicsCard.named("NVIDIA GeForce GTX 1060"))
        #expect(gtx1060 == PCGraphicsCard.named("GTX 1060"), "the maker's name in front is the same card")
        // 180 × 1.3 = 234: past the M1 Pro (200), met by the M5 (240). 16 GB + the card's 6 GB = 22 → 24 GB.
        #expect(MacRequirements.derive(card: gtx1060, memoryGB: 16) == MacRequirement(chip: Self.m5, memoryGB: 24))
        // An old game's card is met by any Apple silicon Mac, with the smallest memory Apple sells.
        let dx8 = try #require(PCGraphicsCard.named("DirectX 8 card"))
        #expect(MacRequirements.derive(card: dx8, memoryGB: 1) == MacRequirement(chip: Self.m1, memoryGB: 8))
        // Memory alone can move the chip: an M1 is never sold with 24 GB.
        let tiny = PCGraphicsCard("test card", score: 10, videoMemoryGB: 4)
        #expect(MacRequirements.derive(card: tiny, memoryGB: 16)?.chip == MacChip(generation: 2, tier: .base))
        // A card beyond every Mac is said to be beyond every Mac, not mapped to the biggest one.
        let monster = PCGraphicsCard("test card", score: 5_000, videoMemoryGB: 24)
        #expect(MacRequirements.derive(card: monster, memoryGB: 64) == nil)
    }

    @Test("A requirement names the other kinds of Mac that draw as well")
    func alternatives() {
        let m5 = MacRequirement(chip: Self.m5, memoryGB: 24)
        #expect(m5.alternatives == [Self.m2Pro, Self.m1Max])
        #expect(MacRequirement(chip: Self.m3Max, memoryGB: 24).alternatives.isEmpty,
                "nothing below a Max draws like an M3 Max, and an Ultra is never offered as the cheaper way in")
    }

    // MARK: - What the player reads

    static let planetCoaster = MacRequirements(
        minimum: MacRequirement(chip: m5, memoryGB: 24),
        recommended: MacRequirement(chip: m3Max, memoryGB: 24))

    @Test("This Mac is compared with both requirements, chip and memory")
    func verdicts() {
        let mac = Self.planetCoaster
        #expect(mac.verdict(for: .init(chip: Self.m1, memoryGB: 8)) == .belowMinimum)
        #expect(mac.verdict(for: .init(chip: Self.m5, memoryGB: 24)) == .minimum)
        #expect(mac.verdict(for: .init(chip: Self.m5, memoryGB: 16)) == .belowMinimum, "the chip is enough, the memory isn't")
        #expect(mac.verdict(for: .init(chip: Self.m4Max, memoryGB: 64)) == .recommended)
        #expect(mac.verdict(for: .init(chip: nil, memoryGB: 32)) == .unknown, "an Intel Mac or a chip Cellar can't read")
        // A chip newer than Cellar knows meets what the chips it replaced vouch for, and no more.
        #expect(mac.verdict(for: .init(chip: MacChip(generation: 9, tier: .base), memoryGB: 32)) == .minimum)
    }

    @Test("The page says both Macs, and this Mac only when there is something true to say")
    func rows() {
        let mac = Self.planetCoaster
        #expect(mac.tag == "Best on M3 Max or better")
        let rows = mac.rows(thisMac: .init(chip: Self.m5, memoryGB: 24))
        #expect(rows.map(\.label) == ["Minimum", "Recommended", "This Mac"])
        #expect(rows[0].value == "M5 · 24 GB memory, or an M2 Pro or M1 Max")
        #expect(rows[1].value == "M3 Max · 24 GB memory")
        #expect(rows[2].value.contains("Expect to lower the graphics settings"))
        #expect(mac.rows(thisMac: .init(chip: nil, memoryGB: 16)).count == 2)
        #expect(mac.rows(thisMac: nil).count == 2)
        #expect(mac.explanation.contains("not tested"), "an estimate always says it is one")
    }

    @Test("Every word about a Mac is plain: no translation-layer jargon")
    func plainWords() {
        let mac = Self.planetCoaster
        let thisMac = MacRequirements.ThisMac(chip: Self.m1, memoryGB: 8)
        let text = ([mac.tag, mac.explanation] + mac.rows(thisMac: thisMac).flatMap { [$0.label, $0.value] })
            .joined(separator: " ").lowercased()
        for word in ["wine", "d3dmetal", "dxvk", "rosetta", "moltenvk", "bottle", "runner", "score", "overhead"] {
            #expect(!text.contains(word), "a player reads '\(word)'")
        }
    }

    // MARK: - Every shipped profile

    static let requiredKeys = [
        MacRequirements.Key.source, MacRequirements.Key.pcGPUMinimum, MacRequirements.Key.pcMemoryMinimum,
        MacRequirements.Key.pcGPURecommended, MacRequirements.Key.pcMemoryRecommended,
        MacRequirements.Key.macMinimum, MacRequirements.Key.macMemoryMinimum,
        MacRequirements.Key.macRecommended, MacRequirements.Key.macMemoryRecommended,
        "requirements_checked",
    ]

    @Test("Every game says which Mac it needs and which it is best on", arguments: ProfileDatabaseTests.slugs)
    func everyProfileHasIt(_ slug: String) throws {
        let fields = try Self.fields(slug)
        for key in Self.requiredKeys {
            #expect(!(fields[key] ?? "").isEmpty, "'\(slug)' has no \(key) in [mac] — see docs/MAC-REQUIREMENTS.md")
        }
        let mac = try #require(MacRequirements(fields: fields), "'\(slug)' names a Mac Cellar can't read")
        #expect(mac.minimum.chip.specs != nil, "'\(slug)': \(mac.minimum.chip) is not a chip Cellar has numbers for")
        #expect(mac.recommended.chip.specs != nil, "'\(slug)': \(mac.recommended.chip) is not a chip Cellar has numbers for")
        #expect(mac.isOrdered, "'\(slug)' recommends less than its minimum")
        for need in [mac.minimum, mac.recommended] {
            #expect(MacRequirements.memorySizes.contains(need.memoryGB), "'\(slug)': \(need.memoryGB) GB is not a size Apple sells")
            #expect(need.memoryGB <= (need.chip.specs?.maxMemoryGB ?? 0), "'\(slug)': no \(need.chip) comes with \(need.memoryGB) GB")
        }
        let checked = fields["requirements_checked"] ?? ""
        #expect(checked.wholeMatch(of: #/\d{4}-\d{2}-\d{2}/#) != nil, "'\(slug)': requirements_checked is a date (YYYY-MM-DD)")
    }

    @Test("Every game's Mac is what the rule gives its publisher's PC, or more with a reason",
          arguments: ProfileDatabaseTests.slugs)
    func everyProfileFollowsTheRule(_ slug: String) throws {
        let fields = try Self.fields(slug)
        let mac = try #require(MacRequirements(fields: fields))
        let sides: [(String, String, String, MacRequirement)] = [
            ("minimum", MacRequirements.Key.pcGPUMinimum, MacRequirements.Key.pcMemoryMinimum, mac.minimum),
            ("recommended", MacRequirements.Key.pcGPURecommended, MacRequirements.Key.pcMemoryRecommended, mac.recommended),
        ]
        for (label, cardKey, memoryKey, stated) in sides {
            let name = fields[cardKey] ?? ""
            let card = try #require(PCGraphicsCard.named(name),
                                    "'\(slug)': the \(label) card '\(name)' is not in PCGraphicsCard.all — add it there with its score")
            let memory = try #require(fields[memoryKey].flatMap { Int($0) }, "'\(slug)': \(memoryKey) is a whole number of GB")
            let derived = try #require(MacRequirements.derive(card: card, memoryGB: memory), "'\(slug)': no Mac covers a \(name)")
            if mac.reason == nil {
                #expect(stated == derived,
                        "'\(slug)': the \(label) Mac is \(stated.chip) / \(stated.memoryGB) GB, but the rule gives \(derived.chip) / \(derived.memoryGB) GB")
            } else {
                #expect(stated.covers(derived),
                        "'\(slug)': a reason lets a profile ask for more than the rule (\(derived.chip) / \(derived.memoryGB) GB), never less")
            }
        }
    }

    @Test("Every game's requirements name where they were read, and that source is credited in About",
          arguments: ProfileDatabaseTests.slugs)
    func everySourceIsCredited(_ slug: String) throws {
        let source = try Self.fields(slug)[MacRequirements.Key.source] ?? ""
        let credited = Credits.sources.map(\.name).filter { source.contains($0) }
        #expect(!credited.isEmpty,
                "'\(slug)': pc_requirements_source \"\(source)\" names no source in Credits.sources — credit it there (Kenneth: credit where credit is due)")
    }

    @Test("The benchmarks behind the chip and card tables are credited")
    func benchmarksAreCredited() {
        #expect(Credits.sources.contains { $0.name == "Notebookcheck" })
    }

    @Test("The real Game.plan path carries the Mac requirements to the game page")
    func planCarriesIt() throws {
        _ = Self.staged
        let plan = try Game.plan(slug: "planet-coaster-2")
        let mac = try #require(plan.facts.macRequirements)
        #expect(mac.minimum.chip == Self.m5)
        #expect(mac.source?.isEmpty == false)
    }
}
