import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// Which language a game and its store client start in. Left to chance, Wine took the locale of
/// whatever shell started Cellar, and a Mac set to English got Steam and Planet Coaster in Dutch.
@Suite(.serialized)
struct GameLanguageTests {

    // MARK: - The Mac's language

    @Test("The Mac's language is read from the preferred languages, not the region",
          arguments: [
            (["en-BE"], GameLanguage.english),          // English Mac in Belgium: English, not Dutch
            (["nl-BE", "en-US"], .dutch),
            (["fr-BE"], .french),
            (["pt-BR"], .brazilianPortuguese),
            (["pt-PT"], .portuguese),
            (["es-ES"], .spanish),
            (["es-MX"], .latinAmericanSpanish),
            (["es-419"], .latinAmericanSpanish),
            (["zh-Hans-CN"], .simplifiedChinese),
            (["zh-Hant-TW"], .traditionalChinese),
            (["zh-HK"], .traditionalChinese),
            (["nb-NO"], .norwegian),
            (["ko-KR"], .korean),
          ])
    func systemLanguage(_ preferred: [String], _ expected: GameLanguage) {
        #expect(GameLanguage.system(preferredLanguages: preferred) == expected)
    }

    @Test("A language Cellar can't run a game in is skipped for the next one the player reads")
    func unsupportedFallsThrough() {
        #expect(GameLanguage.system(preferredLanguages: ["th-TH", "de-DE"]) == .german)
        #expect(GameLanguage.system(preferredLanguages: ["th-TH"]) == .english)
        #expect(GameLanguage.system(preferredLanguages: []) == .english)
    }

    // MARK: - Naming

    @Test("A language can be named by code, Steam's name or its own name, in any case")
    func names() {
        #expect(GameLanguage.named("nl") == .dutch)
        #expect(GameLanguage.named("Dutch") == .dutch)
        #expect(GameLanguage.named("nederlands") == .dutch)
        #expect(GameLanguage.named("pt_BR") == .brazilianPortuguese)
        #expect(GameLanguage.named("brazilian") == .brazilianPortuguese)
        #expect(GameLanguage.named("koreana") == .korean)
        #expect(GameLanguage.named("zh-hans") == .simplifiedChinese)
        #expect(GameLanguage.named("klingon") == nil)
        #expect(GameLanguage.named("") == nil)
    }

    @Test("Every language has a distinct code and Steam name, and a real UTF-8 locale")
    func tableIsConsistent() {
        let all = GameLanguage.allCases
        #expect(Set(all.map(\.code)).count == all.count)
        #expect(Set(all.map(\.steamName)).count == all.count)
        for language in all {
            #expect(language.posixLocale.hasSuffix(".UTF-8"))
            #expect(GameLanguage.named(language.code) == language, "\(language.code) must name itself")
            #expect(GameLanguage.named(language.steamName) == language)
        }
    }

    // MARK: - Layering

    @Test("This game's choice beats every game's, which beats the Mac's")
    func layering() {
        let mac = GameLanguage.english
        #expect(LanguageChoice.resolve(game: nil, global: nil, system: mac)
                == LanguageChoice(language: .english, source: .system))
        #expect(LanguageChoice.resolve(game: nil, global: "de", system: mac)
                == LanguageChoice(language: .german, source: .allGames))
        #expect(LanguageChoice.resolve(game: "nl", global: "de", system: mac)
                == LanguageChoice(language: .dutch, source: .thisGame))
    }

    @Test("A value that isn't a language is ignored, so the layer under it stands")
    func junkIsIgnored() {
        #expect(LanguageChoice.resolve(game: "elvish", global: "fr", system: .english).language == .french)
        #expect(LanguageChoice.resolve(game: nil, global: "", system: .italian).source == .system)
    }

    // MARK: - Where the choices are kept

    @Test("Every game's language round-trips through settings.toml, and reset follows the Mac again")
    func globalSettingRoundTrip() throws {
        TestHome.ensure()
        defer { try? CellarSettings.setLanguage(nil) }
        try CellarSettings.setLanguage(.japanese)
        #expect(CellarSettings.language == "ja")
        #expect(LanguageChoice.global(system: .english) == LanguageChoice(language: .japanese, source: .allGames))
        try CellarSettings.setLanguage(nil)
        #expect(CellarSettings.language == nil)
        #expect(LanguageChoice.global(system: .english).source == .system)
    }

    @Test("A game's language sits beside its performance switches without disturbing them")
    func bottleLanguageKeepsOtherLines() throws {
        let url = TestHome.scratch("language-bottle").appendingPathComponent("bottle.toml")
        try """
        # my notes
        [performance]
        metal_hud = "true"

        [env]
        LANG = "keep-me"
        """.write(to: url, atomically: true, encoding: .utf8)

        try BottleConfig.setLanguage(.dutch, in: url)
        #expect(BottleConfig.language(url) == "nl")
        #expect(BottleConfig.fields(url)["metal_hud"] == "true")
        #expect(BottleConfig.env(url)["LANG"] == "keep-me")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("# my notes"))
        #expect(text.contains("[general]\nlanguage = \"nl\""))

        try BottleConfig.setLanguage(.german, in: url)
        #expect(BottleConfig.language(url) == "de")
        #expect(try String(contentsOf: url, encoding: .utf8).components(separatedBy: "language =").count == 2,
                "changing the language rewrites its line, never adds a second")

        try BottleConfig.setLanguage(nil, in: url)
        #expect(BottleConfig.language(url) == nil)
        #expect(BottleConfig.fields(url)["metal_hud"] == "true")
    }

    @Test("A game plan carries its bottle's language over every game's")
    func planCarriesLanguage() throws {
        TestHome.ensure()
        defer { try? CellarSettings.setLanguage(nil) }
        let slug = TestHome.writeProfile("""
        [game]
        name = "Language Fixture"
        store = "steam"
        steam_appid = "480"
        """, slug: "lang")
        try CellarSettings.setLanguage(.french)
        #expect(try Game.plan(slug: slug).language == LanguageChoice(language: .french, source: .allGames))

        let plan = try Game.plan(slug: slug)
        try BottleConfig.setLanguage(.polish, in: BottleConfig.url(forBottle: plan.bottleName))
        #expect(try Game.plan(slug: slug).language == LanguageChoice(language: .polish, source: .thisGame))
    }

    // MARK: - What Wine and Steam are told

    @Test("Wine is pinned to the language's locale, whatever the caller's shell exported")
    func wineEnvironment() throws {
        let install = try #require(TestHome.installStubRunner())
        let env = WineRunner(install: install, prefix: TestHome.scratch("wine-lang"), language: .dutch).environment()
        #expect(env["LANG"] == "nl_NL.UTF-8")
        #expect(env["LC_ALL"] == "nl_NL.UTF-8", "an inherited LC_ALL would otherwise beat LANG")
        #expect(env["LANGUAGE"] == nil)
    }

    @Test("Without a language, Wine keeps the caller's locale — the runner's --version probe")
    func noLanguageLeavesLocaleAlone() throws {
        let install = try #require(TestHome.installStubRunner())
        let env = WineRunner(install: install, prefix: TestHome.scratch("wine-nolang")).environment()
        #expect(env["LANG"] == ProcessInfo.processInfo.environment["LANG"])
    }

    @Test("Steam's language is read from its own registry key, not another program's")
    func registryLanguage() {
        let userReg = #"""
        WINE REGISTRY Version 2

        [Software\\Other\\App] 1730000000
        "Language"="klingon"

        [Software\\Valve\\Steam] 1730000001
        #time=1db2a0b5c3e7f00
        "AutoLoginUser"="player"
        "Language"="dutch"

        [Software\\Valve\\Steam\\Apps] 1730000002
        "Language"="french"
        """#
        #expect(SteamBottle.registryLanguage(inUserReg: userReg) == "dutch")
        #expect(SteamBottle.registryLanguage(inUserReg: "[Software\\\\Other] 1\n\"Language\"=\"x\"\n") == nil)
    }

    @Test("A game Steam installed in Dutch is switched to the player's language in its appmanifest")
    func appmanifestLanguage() throws {
        let manifest = """
        "AppState"
        {
        \t"appid"\t\t"1834430"
        \t"installdir"\t\t"Planet Coaster 2"
        \t"UserConfig"
        \t{
        \t\t"language"\t\t"dutch"
        \t}
        \t"MountedConfig"
        \t{
        \t\t"language"\t\t"dutch"
        \t}
        }
        """
        let updated = try #require(SteamBottle.manifestText(manifest, language: .english))
        let vdf = try #require(TextVDF.parse(updated))
        #expect(vdf.block(at: ["AppState", "UserConfig"])?.string("language") == "english")
        #expect(vdf.block(at: ["AppState", "MountedConfig"])?.string("language") == "dutch",
                "what is on disk is Steam's to change once it has fetched the files")
        #expect(vdf.block(at: ["AppState"])?.string("installdir") == "Planet Coaster 2")

        #expect(SteamBottle.manifestText(updated, language: .english) == nil, "already right: leave the file alone")
        #expect(SteamBottle.manifestText(#""AppState" { "appid" "1" }"#, language: .english) == nil,
                "no UserConfig language: Steam follows its own, which -language sets")
    }

    @Test("Battle.net's installer gets Blizzard's locale, or English where Blizzard has none")
    func blizzardLocale() {
        #expect(GameLanguage.german.blizzardLocale == "deDE")
        #expect(GameLanguage.latinAmericanSpanish.blizzardLocale == "esMX")
        #expect(GameLanguage.dutch.blizzardLocale == nil)
    }

    // MARK: - settings.toml, shared with the wheel strength

    @Test("The wheel strength round-trips through settings.toml beside the language, and reaches Wine")
    func wheelStrengthSetting() throws {
        TestHome.ensure()
        defer {
            try? CellarSettings.setForceFeedbackStrength(nil)
            try? CellarSettings.setLanguage(nil)
        }
        try CellarSettings.setLanguage(.french)
        try CellarSettings.setForceFeedbackStrength(75)
        #expect(CellarSettings.forceFeedbackStrength == 75)
        #expect(CellarSettings.language == "fr", "writing the strength kept the language")
        #expect(throws: CellarError.self) { try CellarSettings.setForceFeedbackStrength(0) }
        #expect(throws: CellarError.self) { try CellarSettings.setForceFeedbackStrength(101) }
        #expect(CellarSettings.forceFeedbackStrength == 75, "a refused value changes nothing")

        let install = try #require(TestHome.installStubRunner())
        let env = WineRunner(install: install, prefix: TestHome.scratch("wine-strength")).environment()
        #expect(env["CELLAR_FFB_MAX_PERCENT"] == "75")
        #expect(env["SDL_HAPTIC_LG4FF_GAIN"] == "49151")

        try CellarSettings.setForceFeedbackStrength(nil)
        #expect(CellarSettings.forceFeedbackStrength == nil)
        let reset = WineRunner(install: install, prefix: TestHome.scratch("wine-strength")).environment()
        #expect(reset["SDL_HAPTIC_LG4FF_GAIN"] == ProcessInfo.processInfo.environment["SDL_HAPTIC_LG4FF_GAIN"])
    }
}
