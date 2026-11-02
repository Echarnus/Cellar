import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Retina, MetalFX and the frame-rate overlay can be set once for every game in Settings
/// (Kenneth, #266). The choice is a layer under the profile and the game's own page.
@Suite("Every-game display settings")
struct EveryGameSettingsTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString).toml")
    }

    @Test("Set for every game, a game nobody said anything about follows it")
    func followsEveryGame() {
        let resolved = PerformanceSettings.resolve(everyGame: ["retina": "true", "metal_hud": "true"],
                                                   profileFields: [:], profileEnv: [:], bottleFields: [:], bottleEnv: [:])
        #expect(resolved.value(.retina) == "true")
        #expect(resolved.metalHUD)
        #expect(resolved.env["MTL_HUD_ENABLED"] == "1", "the overlay reaches the game's environment")
        #expect(resolved.entries.first { $0.setting == .retina }?.source == .everyGame,
                "a non-default source, so the launch writes Retina into the registry")
    }

    @Test("The profile and then the game's own page win over the every-game choice")
    func layering() {
        let profile = PerformanceSettings.resolve(everyGame: ["metalfx_upscaling": "true"],
                                                  profileFields: ["metalfx_upscaling": "false"], profileEnv: [:],
                                                  bottleFields: [:], bottleEnv: [:])
        #expect(!profile.metalFXUpscaling)
        let page = PerformanceSettings.resolve(everyGame: ["metal_hud": "true"], profileFields: [:], profileEnv: [:],
                                               bottleFields: ["metal_hud": "false"], bottleEnv: [:])
        #expect(!page.metalHUD)
        #expect(page.env["MTL_HUD_ENABLED"] == nil)
    }

    @Test("Settings writes and reads the three switches, and only those")
    func roundTrip() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        for setting in CellarSettings.everyGameSettings {
            #expect(!CellarSettings.isOn(setting, at: url))
            try CellarSettings.set(setting, on: true, at: url)
            #expect(CellarSettings.isOn(setting, at: url))
        }
        try CellarSettings.set(.retina, on: false, at: url)
        #expect(!CellarSettings.isOn(.retina, at: url))
        #expect(throws: CellarError.self) { try CellarSettings.set(.metalValidation, on: true, at: url) }
        // A hand-written crash workaround in the shared file is not applied to every game.
        try "metal_validation = \"true\"\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(CellarSettings.performance(at: url).isEmpty)
    }

    @Test("Verification names an every-game choice as a difference from the profile")
    func verifyNamesIt() {
        let entries = PerformanceSettings.resolve(everyGame: ["retina": "true"], profileFields: [:], profileEnv: [:],
                                                  bottleFields: [:], bottleEnv: [:]).entries
        let check = VerifyGame.judgeSettings(entries, language: LanguageChoice.global(system: .english), macLanguage: .english)
        #expect(check.verdict == .fail)
        #expect(check.evidence.contains { $0.contains("for every game") })
    }
}

/// The Steam account's own picture beside its name in the sidebar (Kenneth, #266).
@Suite("Steam avatar")
struct SteamAvatarTests {
    @Test("The SteamID comes from the client's login users, matched like Steam matches names")
    func steamID() {
        let vdf = TextVDF.parse("""
            "users"
            {
                "76561198000000001"
                {
                    "AccountName"   "someoneelse"
                }
                "76561198012345678"
                {
                    "AccountName"   "KennethDC"
                    "MostRecent"    "1"
                }
            }
            """)
        #expect(SteamAvatar.steamID(for: "kennethdc", loginUsers: vdf) == "76561198012345678")
        #expect(SteamAvatar.steamID(for: "nobody", loginUsers: vdf) == nil)
        #expect(!SteamAvatar.isSteamID("12345"))
    }

    @Test("Only a picture on Steam's own image hosts, over HTTPS, is taken from the profile")
    func avatarURL() {
        let xml = "<profile><avatarFull><![CDATA[https://avatars.fastly.steamstatic.com/abc_full.jpg]]></avatarFull></profile>"
        #expect(SteamAvatar.avatarURL(inProfileXML: xml)?.absoluteString == "https://avatars.fastly.steamstatic.com/abc_full.jpg")
        #expect(SteamAvatar.avatarURL(inProfileXML: "<avatarFull><![CDATA[http://avatars.steamstatic.com/a.jpg]]></avatarFull>") == nil)
        #expect(SteamAvatar.avatarURL(inProfileXML: "<avatarFull><![CDATA[https://evil.example/a.jpg]]></avatarFull>") == nil)
        #expect(SteamAvatar.avatarURL(inProfileXML: "<error>The specified profile could not be found.</error>") == nil)
    }

    @Test("Each account keeps its own picture, so a new sign-in never shows the last one's face")
    func perAccountFile() throws {
        let shared = FileManager.default.temporaryDirectory.appendingPathComponent("avatar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: shared) }
        #expect(SteamAvatar.file(for: "a", in: shared) != SteamAvatar.file(for: "b", in: shared))
        #expect(SteamAvatar.file(for: "../x", in: shared).deletingLastPathComponent().standardizedFileURL.path
                == shared.standardizedFileURL.path, "an account name can't climb out of the folder")
        #expect(SteamAvatar.localFile(for: "a", in: shared) == nil)
        #expect(SteamAvatar.isStale(for: "a", in: shared))
        try Data([1]).write(to: SteamAvatar.file(for: "a", in: shared))
        #expect(SteamAvatar.localFile(for: "a", in: shared) != nil)
        #expect(!SteamAvatar.isStale(for: "a", in: shared))
        #expect(SteamAvatar.isStale(for: "a", in: shared, now: Date().addingTimeInterval(8 * 24 * 3600)))
        SteamAvatar.forget("a", in: shared)
        #expect(SteamAvatar.localFile(for: "a", in: shared) == nil)
    }
}
