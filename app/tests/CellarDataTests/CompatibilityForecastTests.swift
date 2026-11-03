import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Cellar's estimate for games nobody has tested (#286, `docs/COMPATIBILITY.md`).
///
/// The rule that matters most is honesty: a test always wins over the estimate, a guess never
/// reads as a result, and thin evidence never says "Should work".
@Suite
struct CompatibilityForecastTests {

    private func forecast(status: String? = "untested", api: String? = nil, engine: String? = nil,
                          anticheat: String? = nil, drm: String? = nil, architecture: String? = "x86-64",
                          runner: String = "wineforge", backend: String = "d3dmetal", fallback: String? = nil,
                          launcher: PublisherLauncher? = nil,
                          evidence: CompatibilityEvidence = CompatibilityEvidence()) -> CompatibilityForecast {
        CompatibilityForecast(CompatibilitySignals(
            facts: GameFacts(engine: engine, graphicsAPI: api, anticheat: anticheat, drm: drm, status: status,
                             architecture: architecture, evidence: evidence),
            runnerID: runner, backend: backend, fallbackBackend: fallback, launcher: launcher))
    }

    // MARK: - A test wins

    @Test("A tested game says what the test found, whatever the estimate would say")
    func testedWins() {
        let played = forecast(status: "playable", api: "Vulkan", anticheat: "Easy Anti-Cheat")
        #expect(played.outlook == .works)
        #expect(played.basis == .tested)
        #expect(played.title == "Works")

        let broken = forecast(status: "broken", api: "DirectX 11", anticheat: "none",
                              evidence: CompatibilityEvidence(protonDB: "platinum"))
        #expect(broken.outlook == .wontWork)
        #expect(broken.basis == .tested)
        #expect(broken.title == "Doesn't work yet")
    }

    @Test("An estimate never claims to be a test, in its words or its basis")
    func estimateSaysSo() {
        let f = forecast(api: "DirectX 11", anticheat: "none", fallback: "dxvk",
                         evidence: CompatibilityEvidence(protonDB: "platinum", steamDeck: "verified"))
        #expect(f.basis == .estimate)
        #expect(f.outlook == .likely)
        #expect(f.title == "Should work")
        #expect(f.detail.contains("Not tested"))
    }

    // MARK: - Evidence

    @Test("Without public reports or a Cellar lesson, the best an estimate says is Might work")
    func thinEvidenceCaps() {
        let f = forecast(api: "DirectX 11", anticheat: "none", fallback: "dxvk")
        #expect(f.score >= 4, "the facts alone add up to Should work")
        #expect(f.evidenceCount < 2)
        #expect(f.outlook == .unsure)
    }

    @Test("Linux players' reports move the estimate both ways", arguments: [
        ("platinum", CompatibilityForecast.Outlook.likely), ("borked", .unlikely),
    ])
    func protonDBMoves(_ tier: String, _ expected: CompatibilityForecast.Outlook) {
        let f = forecast(api: "DirectX 11", anticheat: "none",
                         evidence: CompatibilityEvidence(protonDB: tier))
        #expect(f.outlook == expected)
        #expect(f.reasons.contains { $0.source == "ProtonDB" })
    }

    @Test("Missing or placeholder evidence counts as none")
    func placeholderEvidence() {
        let e = CompatibilityEvidence(fields: ["protondb": "pending", "steam_deck": " ", "anticheat_on_linux": "unknown"])
        #expect(e.isEmpty)
        let read = CompatibilityEvidence(fields: ["protondb": "Gold", "steam_deck": "Verified", "evidence_checked": "2026-11-03"])
        #expect(read.protonDB == "gold")
        #expect(read.steamDeck == "verified")
        #expect(read.checked == "2026-11-03")
    }

    @Test("Mac players' reports outweigh Linux ones: a game Mac players see fail is not Should work")
    func macReportsWin() {
        let fails = forecast(api: "Vulkan", anticheat: "none",
                             evidence: CompatibilityEvidence(protonDB: "gold", steamDeck: "verified", onMac: "fails"))
        #expect(fails.outlook == .unlikely)
        let runs = forecast(api: "DirectX 12", anticheat: "none", evidence: CompatibilityEvidence(onMac: "runs"))
        #expect(runs.evidenceCount == 2)
        #expect(runs.score > forecast(api: "DirectX 12", anticheat: "none").score)
    }

    @Test("Enshrouded, which Mac players report not starting, is never estimated to work")
    func enshrouded() throws {
        let fields = try #require(Self.shipped().first { $0.slug == "enshrouded" }?.fields)
        #expect(Self.forecast(fields).outlook <= .unlikely)
    }

    // MARK: - Anti-cheat

    @Test("An anti-cheat that only accepts Windows itself means Won't work, whatever else is true")
    func kernelAntiCheatBlocks() {
        let f = forecast(api: "DirectX 11", anticheat: "Riot Vanguard (kernel-level)",
                         evidence: CompatibilityEvidence(protonDB: "platinum", steamDeck: "verified"))
        #expect(f.outlook == .wontWork)
        #expect(f.basis == .estimate)
        #expect(f.title == "Won't work")
        #expect(f.reasons.contains { $0.effect == .blocks })
    }

    @Test("Saying an anti-cheat is not kernel-level never reads as one that is")
    func notKernel() {
        #expect(CompatibilityForecast.anticheat("vac (valve anti-cheat, user space, not kernel-level)") == .valve)
        #expect(CompatibilityForecast.anticheat("blizzard's own (in the game process, not kernel-level)") == .other)
        #expect(CompatibilityForecast.anticheat("none known (no easyanticheat or battleye)") == .none)
        #expect(CompatibilityForecast.anticheat("none in story mode; red dead online not tried under cellar") == .none)
    }

    @Test("Online-only Easy Anti-Cheat costs a little and gets its own sentence; required costs a lot")
    func easyAntiCheat() {
        let onlineOnly = forecast(api: "DirectX 12", anticheat: "Easy Anti-Cheat (online play only)")
        let required = forecast(api: "DirectX 12", anticheat: "Easy Anti-Cheat")
        #expect(onlineOnly.online?.contains("Easy Anti-Cheat") == true)
        #expect(required.score < onlineOnly.score)
        #expect(required.outlook == .unlikely)
    }

    @Test("A publisher that blocks its anti-cheat outside Windows is named in the online sentence")
    func deniedOnline() {
        let f = forecast(api: "DirectX 11", anticheat: "BattlEye (GTA Online only)",
                         evidence: CompatibilityEvidence(anticheatOnLinux: "denied"))
        #expect(f.online?.contains("won't work") == true)
    }

    // MARK: - Graphics and Cellar's lessons

    @Test("The friendliest graphics a game offers is the one weighed", arguments: [
        ("DirectX 11", "dx11"), ("DirectX 10 or later", "dx9or10"), ("Vulkan or DirectX 12", "dx12"),
        ("Direct3D 9", "dx9or10"), ("Vulkan", "vulkan"), ("OpenGL 4", "openGL"), ("not published", "unknown"),
    ])
    func graphicsRead(_ api: String, _ expected: String) {
        #expect("\(CompatibilityForecast.graphics(api.lowercased()))" == expected)
    }

    @Test("A Bethesda game is weighed on what Skyrim needed (#246)")
    func creationEngineLesson() {
        let without = forecast(api: "DirectX 11", engine: "Creation Engine")
        let with = forecast(api: "DirectX 11", engine: "Creation Engine", runner: "wineforge-d3dmetal4")
        #expect(with.score > without.score)
        #expect(with.reasons.contains { $0.source == "#246" && $0.effect == .helps })
        #expect(without.reasons.contains { $0.source == "#246" && $0.effect == .hurts })
    }

    @Test("A Frontier game carries the online fix Planet Coaster 2 needed (#261)")
    func frontierLesson() {
        let f = forecast(api: "DirectX 12", engine: "COBRA")
        #expect(f.reasons.contains { $0.source == "#261" })
    }

    @Test("A launcher Cellar can't set up counts against the game")
    func unsupportedLauncher() {
        let f = forecast(api: "DirectX 11", anticheat: "none", drm: "EA app account required")
        #expect(f.reasons.contains { $0.text.contains("EA app") && $0.effect == .hurts })
    }

    @Test("The player's words never name Wine or a graphics translator")
    func plainWords() {
        let all = [
            forecast(api: "DirectX 11", engine: "Creation Engine", anticheat: "Easy Anti-Cheat", drm: "Denuvo",
                     architecture: "x86", fallback: "dxvk", launcher: .rockstar,
                     evidence: CompatibilityEvidence(protonDB: "gold", steamDeck: "playable", anticheatOnLinux: "supported")),
            forecast(api: "Vulkan", engine: "COBRA", anticheat: "Vanguard"),
            forecast(api: nil),
        ]
        for f in all {
            let words = ([f.title, f.detail, f.online ?? ""] + f.reasons.map(\.text)).joined(separator: " ").lowercased()
            for banned in ["wine", "d3dmetal", "dxvk", "moltenvk", "bottle", "prefix", "runner", "proton "] {
                #expect(!words.contains(banned), "\(banned) in: \(words)")
            }
        }
    }

    // MARK: - The shipped profiles

    private static func shipped() -> [(slug: String, fields: [String: String])] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Repo.profiles, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "toml" }.map { url in
            let slug = url.deletingPathExtension().lastPathComponent
            return (slug, ProfileStore.fields(ProfileRef(slug: slug, url: url)))
        }.sorted { $0.slug < $1.slug }
    }

    private static func forecast(_ fields: [String: String]) -> CompatibilityForecast {
        CompatibilityForecast(CompatibilitySignals(
            facts: GameFacts(engine: fields["engine"], graphicsAPI: fields["graphics_api"],
                             anticheat: fields["anticheat"], drm: fields["drm"], status: fields["status"],
                             architecture: fields["architecture"], evidence: CompatibilityEvidence(fields: fields)),
            store: GameStore(profileValue: fields["store"]) ?? .steam,
            runnerID: fields["id"] ?? "wineforge", backend: fields["backend"] ?? "d3dmetal",
            fallbackBackend: fields["fallback_backend"],
            launcher: PublisherLauncher(profileValue: fields["publisher_launcher"])))
    }

    @Test("Every shipped profile gets a forecast with reasons, and only a tested one says Works")
    func everyShippedProfile() {
        let profiles = Self.shipped()
        #expect(profiles.count > 20)
        for (slug, fields) in profiles {
            let f = Self.forecast(fields)
            #expect(!f.reasons.isEmpty, "\(slug) has no reasons")
            let tested = (fields["status"] ?? "").lowercased().hasPrefix("playable")
            #expect((f.outlook == .works) == tested, "\(slug): \(f.title)")
        }
    }

    @Test("Shipped evidence uses only the values the forecast knows")
    func shippedEvidenceVocabulary() {
        let known: [String: Set<String>] = [
            "protondb": ["platinum", "gold", "silver", "bronze", "borked", "pending"],
            "steam_deck": ["verified", "playable", "unsupported", "unknown"],
            "anticheat_on_linux": ["supported", "running", "planned", "broken", "denied"],
            "mac_reports": ["runs", "issues", "fails"],
        ]
        for (slug, fields) in Self.shipped() {
            for (key, values) in known {
                if let value = fields[key] { #expect(values.contains(value.lowercased()), "\(slug): \(key) = \(value)") }
            }
            if fields["protondb"] != nil || fields["steam_deck"] != nil {
                #expect(fields["evidence_checked"] != nil, "\(slug) has public reports without the date they were read")
            }
        }
    }

    @Test("Elden Ring's estimate names Easy Anti-Cheat for online play, and never says Should work")
    func eldenRing() throws {
        let fields = try #require(Self.shipped().first { $0.slug == "elden-ring" }?.fields)
        let f = Self.forecast(fields)
        #expect(f.outlook < .likely)
        #expect(f.online?.contains("Easy Anti-Cheat") == true)
    }

    @Test("The library reads the forecast through the real profile path")
    func throughGamePlan() throws {
        let source = Repo.profiles.appendingPathComponent("elden-ring.toml")
        let target = TestHome.profilesDirectory.appendingPathComponent("elden-ring.toml")
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
        let plan = try Game.plan(slug: "elden-ring")
        #expect(plan.facts.architecture == "x86-64")
        #expect(plan.forecast == Self.forecast(ProfileStore.fields(ProfileRef(slug: "elden-ring", url: source))))
    }
}
