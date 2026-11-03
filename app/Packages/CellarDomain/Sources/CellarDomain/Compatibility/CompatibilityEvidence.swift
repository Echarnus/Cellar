import Foundation

/// What people outside Cellar report about a game, copied into its profile from public sources by
/// `app/Scripts/refresh-evidence.py` (run weekly by `.github/workflows/evidence.yml`).
///
/// All of it is about **Linux**, not the Mac: Valve's Proton is Wine too, so a game that runs well
/// there has cleared most of what stops a Windows game under a translation layer. It is evidence
/// for the estimate, never a status, and never a ✓ — see `docs/COMPATIBILITY.md`.
public struct CompatibilityEvidence: Sendable, Equatable {
    /// ProtonDB's summary tier: `platinum` / `gold` / `silver` / `bronze` / `borked`.
    public let protonDB: String?
    /// Valve's Steam Deck rating: `verified` / `playable` / `unsupported`.
    public let steamDeck: String?
    /// AreWeAntiCheatYet's word on the game's anti-cheat under Proton:
    /// `supported` / `running` / `planned` / `broken` / `denied`.
    public let anticheatOnLinux: String?
    /// When the values above were read (`YYYY-MM-DD`).
    public let checked: String?

    public init(protonDB: String? = nil, steamDeck: String? = nil, anticheatOnLinux: String? = nil,
                checked: String? = nil) {
        self.protonDB = Self.clean(protonDB)
        self.steamDeck = Self.clean(steamDeck)
        self.anticheatOnLinux = Self.clean(anticheatOnLinux)
        self.checked = checked
    }

    /// Profile fields: `protondb`, `steam_deck`, `anticheat_on_linux`, `evidence_checked`.
    public init(fields: [String: String]) {
        self.init(protonDB: fields["protondb"], steamDeck: fields["steam_deck"],
                  anticheatOnLinux: fields["anticheat_on_linux"], checked: fields["evidence_checked"])
    }

    /// Whether any public source has said anything about the game.
    public var isEmpty: Bool { protonDB == nil && steamDeck == nil && anticheatOnLinux == nil }

    private static func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces).lowercased(),
              !value.isEmpty, value != "unknown", value != "pending" else { return nil }
        return value
    }
}
