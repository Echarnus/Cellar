import Foundation

/// How likely a game is to work under Cellar, and why — for the games nobody has tested yet.
///
/// Kenneth cannot play every game, and "untested" alone told a player nothing: Stardew Valley and
/// a DirectX 12 game behind Easy Anti-Cheat read the same. This turns what is known into an honest
/// estimate (`docs/COMPATIBILITY.md`):
///
/// 1. **A test always wins.** `status = "playable"` is *Works*; `broken` is *Doesn't work yet*.
/// 2. **Hard blockers** — an anti-cheat that only accepts real Windows — say *Won't work*.
/// 3. Otherwise every fact adds or takes away a little: how the game draws, whether Cellar has a
///    second way to draw it, its anti-cheat, its extra launchers, what Cellar learned on a game
///    built the same way, and how it runs for Linux players (`CompatibilityEvidence`).
/// 4. **Thin evidence never says "Should work"**: with fewer than two independent facts behind it,
///    the best an estimate says is *Might work*.
///
/// The words are the player's (`docs/DESIGN.md`): no Wine, no backends, and never a ✓ for a game
/// nobody tested.
public struct CompatibilityForecast: Sendable, Equatable {

    public enum Outlook: Int, Sendable, Comparable, CaseIterable {
        case wontWork, unlikely, unsure, likely, works
        public static func < (a: Outlook, b: Outlook) -> Bool { a.rawValue < b.rawValue }
    }

    /// Whether a person has run the game under Cellar, or this is Cellar's estimate.
    public enum Basis: Sendable, Equatable { case tested, estimate }

    public struct Reason: Sendable, Equatable {
        public enum Effect: Sendable, Equatable { case helps, hurts, blocks, note }
        public let effect: Effect
        /// One plain sentence.
        public let text: String
        /// Where Cellar learned it: an issue or PR (`#246`) or a public source. Nil for a fact
        /// read straight from the profile.
        public let source: String?

        public init(_ effect: Effect, _ text: String, source: String? = nil) {
            self.effect = effect; self.text = text; self.source = source
        }

        /// A sign for the CLI and Technical Details.
        public var symbol: String {
            switch effect {
            case .helps: return "+"
            case .hurts: return "−"
            case .blocks: return "✗"
            case .note: return "·"
            }
        }
    }

    public let outlook: Outlook
    public let basis: Basis
    /// Every fact that moved the estimate, in the order it was weighed.
    public let reasons: [Reason]
    /// A sentence about online play when it differs from the rest of the game, else nil.
    public let online: String?
    /// The sum the outlook came from. Kept for `cellar profiles forecast` and the tests.
    public let score: Int
    /// How many independent kinds of evidence back an estimate (graphics, public reports, a Cellar
    /// lesson). Below two, an estimate never says "Should work".
    public let evidenceCount: Int

    // MARK: - Words

    /// The badge on the game page.
    public var title: String {
        switch (outlook, basis) {
        case (.works, _):              return String(localized: "Works")
        case (.likely, _):             return String(localized: "Should work")
        case (.unsure, _):             return String(localized: "Might work")
        case (.unlikely, _):           return String(localized: "Unlikely to work")
        case (.wontWork, .tested):     return String(localized: "Doesn't work yet")
        case (.wontWork, .estimate):   return String(localized: "Won't work")
        }
    }

    /// One sentence under the badge: what the title is based on.
    public var detail: String {
        switch basis {
        case .tested:
            return outlook == .works
                ? String(localized: "Tested with Cellar on a Mac.")
                : String(localized: "Tested with Cellar on a Mac, and it didn't run.")
        case .estimate:
            return outlook == .wontWork
                ? String(localized: "Not tested with Cellar. Something this game needs only runs on Windows itself.")
                : String(localized: "Not tested with Cellar yet. This is Cellar's estimate from how the game is built and how it runs for other players.")
        }
    }

    // MARK: - The estimate

    public init(_ s: CompatibilitySignals) {
        var reasons: [Reason] = []
        var score = 0
        var evidence = 0
        var blocked = false
        var online: String?

        let status = s.lower(s.facts.status)
        if status.hasPrefix("playable") {
            self.init(outlook: .works, basis: .tested,
                      reasons: [Reason(.helps, String(localized: "Played with Cellar on a Mac."))],
                      online: nil, score: 0, evidenceCount: 1)
            return
        }
        if status.hasPrefix("broken") || status.hasPrefix("unplayable") {
            self.init(outlook: .wontWork, basis: .tested,
                      reasons: [Reason(.blocks, String(localized: "Tried with Cellar on a Mac, and it didn't run."))],
                      online: nil, score: 0, evidenceCount: 1)
            return
        }
        if status.hasPrefix("experimental") {
            score += 2
            evidence += 1
            reasons.append(Reason(.helps, String(localized: "It has started with Cellar, but nobody has played it through yet.")))
        }

        // How the game draws.
        let graphics = Self.graphics(s.lower(s.facts.graphicsAPI))
        switch graphics {
        case .dx11:
            score += 2; evidence += 1
            reasons.append(Reason(.helps, String(localized: "It draws with DirectX 11, which Cellar's graphics handle best.")))
        case .dx9or10:
            score += 1; evidence += 1
            reasons.append(Reason(.helps, String(localized: "It draws with an older DirectX, which Cellar can run.")))
        case .dx12:
            evidence += 1
            reasons.append(Reason(.note, String(localized: "It draws with DirectX 12, which a Mac runs only one way.")))
        case .vulkan:
            score -= 1; evidence += 1
            reasons.append(Reason(.hurts, String(localized: "It draws with Vulkan, which reaches the Mac through more layers and has been tried least.")))
        case .openGL:
            evidence += 1
            reasons.append(Reason(.note, String(localized: "It draws with OpenGL, which the Mac only supports in an old version.")))
        case .unknown:
            reasons.append(Reason(.note, String(localized: "Cellar doesn't know how it draws, so this estimate leans on the rest.")))
        }
        if let fallback = s.fallbackBackend, !fallback.isEmpty, fallback != s.backend {
            score += 1
            reasons.append(Reason(.helps, String(localized: "If it doesn't start, Cellar has a second way to run its graphics to try.")))
        }

        if s.lower(s.facts.architecture) == "x86" {
            reasons.append(Reason(.note, String(localized: "It's a 32-bit game. Cellar runs those, but fewer have been tried.")))
        }

        // Anti-cheat: the one thing that can stop a game outright.
        let anticheat = s.lower(s.facts.anticheat)
        let onLinux = s.facts.evidence.anticheatOnLinux
        switch Self.anticheat(anticheat) {
        case .none:
            score += 1
            reasons.append(Reason(.helps, String(localized: "No anti-cheat to get in the way.")))
        case .valve:
            score += 1
            reasons.append(Reason(.helps, String(localized: "Its anti-cheat is Valve's own, which doesn't stop a game outside Windows.")))
        case .kernel:
            blocked = true
            reasons.append(Reason(.blocks, String(localized: "Its anti-cheat only accepts Windows itself, so it refuses to start anywhere else.")))
        case .protected(let onlineOnly):
            let name = anticheat.contains("battleye") ? "BattlEye" : "Easy Anti-Cheat"
            if onLinux == "denied" {
                online = String(localized: "Online play won't work: the publisher blocks \(name) outside Windows.")
            } else {
                online = String(localized: "Online play needs \(name), which hasn't been seen working on a Mac.")
            }
            if onlineOnly {
                score -= 1
                reasons.append(Reason(.hurts, String(localized: "\(name) guards its online play and starts with the game. It hasn't been seen working on a Mac.")))
            } else {
                score -= 3
                reasons.append(Reason(.hurts, String(localized: "It won't start without \(name), which hasn't been seen working on a Mac.")))
            }
            if onLinux == "supported" || onLinux == "running" {
                reasons.append(Reason(.note, String(localized: "On Linux it runs with its anti-cheat, but that relies on a part only Linux has, so it says little about a Mac."),
                                      source: "AreWeAntiCheatYet"))
            }
        case .other:
            reasons.append(Reason(.note, String(localized: "It has an anti-cheat of its own, which Cellar hasn't seen refuse a Mac.")))
        case .unknown:
            break
        }

        // Extra launchers between the store and the game.
        let drm = s.lower(s.facts.drm)
        if s.launcher == .rockstar {
            reasons.append(Reason(.note, String(localized: "It starts through the Rockstar Games Launcher, which Cellar sets up for it."), source: "#267"))
        }
        if let other = Self.unsupportedLauncher(drm) {
            score -= 2
            reasons.append(Reason(.hurts, String(localized: "It also needs \(other), which Cellar can't set up yet.")))
        }
        if drm.contains("denuvo") {
            reasons.append(Reason(.note, String(localized: "Its copy protection may count your Mac as a new PC the first time it starts.")))
        }

        // What Cellar learned on games built the same way.
        let engine = s.lower(s.facts.engine)
        if engine.contains("creation engine") || engine.contains("gamebryo") {
            evidence += 1
            if s.runnerID.contains("d3dmetal4") {
                score += 1
                reasons.append(Reason(.helps, String(localized: "Skyrim is built the same way and runs with Cellar, with the newer graphics it needed."), source: "#246"))
            } else {
                score -= 1
                reasons.append(Reason(.hurts, String(localized: "Skyrim, built the same way, needed newer graphics before it would start, and this game isn't set up with them yet."), source: "#246"))
            }
        }
        if engine.contains("cobra") {
            evidence += 1
            score += 1
            reasons.append(Reason(.helps, String(localized: "Planet Coaster 2 is built the same way, and Cellar carries the fix that brought its online features back."), source: "#261"))
        }

        // How it runs for Linux players, through the same kind of layer.
        let e = s.facts.evidence
        if let tier = e.protonDB {
            let points = ["platinum": 3, "gold": 2, "silver": 1, "bronze": 0, "borked": -3][tier]
            if let points {
                score += points
                let effect: Reason.Effect = points > 0 ? .helps : (points < 0 ? .hurts : .note)
                reasons.append(Reason(effect, String(localized: "On Linux, which runs Windows games much like Cellar does, players rate it \(tier.capitalized)."),
                                      source: "ProtonDB"))
            }
        }
        if let deck = e.steamDeck {
            let points = ["verified": 1, "playable": 1, "unsupported": -1][deck]
            if let points {
                score += points
                reasons.append(Reason(points > 0 ? .helps : .hurts,
                                      String(localized: "Valve rates it \(deck.capitalized) on Steam Deck."),
                                      source: "Steam Deck"))
            }
        }
        if e.protonDB != nil || e.steamDeck != nil { evidence += 1 }

        var outlook: Outlook
        if blocked { outlook = .wontWork }
        else if score >= 4 { outlook = .likely }
        else if score >= 1 { outlook = .unsure }
        else { outlook = .unlikely }
        // Thin evidence never says "Should work".
        if outlook == .likely && evidence < 2 { outlook = .unsure }

        self.init(outlook: outlook, basis: .estimate, reasons: reasons, online: online,
                  score: score, evidenceCount: evidence)
    }

    init(outlook: Outlook, basis: Basis, reasons: [Reason], online: String?, score: Int, evidenceCount: Int) {
        self.outlook = outlook
        self.basis = basis
        self.reasons = reasons
        self.online = online
        self.score = score
        self.evidenceCount = evidenceCount
    }

    // MARK: - Reading the profile's words

    public enum Graphics: Sendable { case dx11, dx9or10, dx12, vulkan, openGL, unknown }

    /// The friendliest API a game offers: "Vulkan or DirectX 12" is DirectX 12, "DirectX 10 or
    /// later" is DirectX 10.
    public static func graphics(_ api: String) -> Graphics {
        let a = api.replacingOccurrences(of: "direct3d", with: "directx").replacingOccurrences(of: "dx", with: "directx ")
        if a.contains("directx 11") { return .dx11 }
        if a.contains("directx 9") || a.contains("directx 10") { return .dx9or10 }
        if a.contains("directx 12") { return .dx12 }
        if a.contains("vulkan") { return .vulkan }
        if a.contains("opengl") { return .openGL }
        return .unknown
    }

    public enum AntiCheat: Sendable, Equatable { case none, valve, kernel, protected(onlineOnly: Bool), other, unknown }

    /// The profile's `anticheat` words, read the way people write them ("none (single-player
    /// only)", "VAC (… not kernel-level)", "Easy Anti-Cheat (online play only)").
    public static func anticheat(_ text: String) -> AntiCheat {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return .unknown }
        if t.hasPrefix("none") || t.hasPrefix("no ") { return .none }
        let kernelNames = ["vanguard", "faceit", "ricochet", "nprotect", "gameguard", "xigncode", "mhyprot", "javelin"]
        if kernelNames.contains(where: { t.contains($0) }) { return .kernel }
        if t.contains("easy anti-cheat") || t.contains("easyanticheat") || t.hasPrefix("eac") || t.contains("(eac") || t.contains("battleye") {
            return .protected(onlineOnly: t.contains("only"))
        }
        if t.hasPrefix("vac") || t.contains("valve anti-cheat") { return .valve }
        if t.contains("kernel") && !t.contains("not kernel") { return .kernel }
        return .other
    }

    /// A publisher launcher the game needs that Cellar has no setup for.
    public static func unsupportedLauncher(_ drm: String) -> String? {
        if drm.contains("ea app") || drm.contains("origin") { return "the EA app" }
        if drm.contains("ubisoft") || drm.contains("uplay") { return "Ubisoft Connect" }
        if drm.contains("epic online") || drm.contains("epic games launcher") { return "the Epic Games Launcher" }
        return nil
    }
}
