import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// The per-game performance switches: Wine debug tracing, the Metal validation layer, MetalFX
/// upscaling and the Metal performance HUD. Each one is a few frames per second or a crash
/// workaround, and a layering slip — the profile quietly beating the player's own choice — is
/// invisible until someone wonders why their FPS did not move.
@Suite(.serialized)
struct PerformanceSettingsTests {

    // MARK: - Helpers

    private func resolve(profileFields: [String: String] = [:],
                         profileEnv: [String: String] = [:],
                         bottleFields: [String: String] = [:],
                         bottleEnv: [String: String] = [:]) -> PerformanceSettings.Resolved {
        PerformanceSettings.resolve(profileFields: profileFields, profileEnv: profileEnv,
                                    bottleFields: bottleFields, bottleEnv: bottleEnv)
    }

    private func entry(_ setting: PerformanceSetting,
                       in resolved: PerformanceSettings.Resolved) throws -> PerformanceSettings.Entry {
        try #require(resolved.entries.first { $0.setting == setting })
    }

    private func bottleFile(_ contents: String? = nil) throws -> URL {
        let url = TestHome.scratch("perf-bottle").appendingPathComponent("bottle.toml")
        if let contents { try contents.write(to: url, atomically: true, encoding: .utf8) }
        return url
    }

    private func lines(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
    }

    /// Lines that assign `key`, ignoring comments.
    private func assignments(of key: String, in url: URL) throws -> [String] {
        try lines(url).filter {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { return false }
            return trimmed[..<eq].trimmingCharacters(in: .whitespaces) == key
        }
    }

    // MARK: - PerformanceSetting

    @Test("Each setting's key is its TOML key")
    func rawValuesAreTomlKeys() {
        #expect(PerformanceSetting.wineDebug.rawValue == "wine_debug")
        #expect(PerformanceSetting.metalValidation.rawValue == "metal_validation")
        #expect(PerformanceSetting.metalFXUpscaling.rawValue == "metalfx_upscaling")
        #expect(PerformanceSetting.metalHUD.rawValue == "metal_hud")
        #expect(Set(PerformanceSetting.allCases.map(\.rawValue))
                == ["wine_debug", "metal_validation", "metalfx_upscaling", "metal_hud", "retina"])
    }

    @Test("named() finds every setting by its key and nothing else")
    func namedLookup() {
        for setting in PerformanceSetting.allCases {
            #expect(PerformanceSetting.named(setting.rawValue) == setting)
        }
        #expect(PerformanceSetting.named("no_such_setting") == nil)
        #expect(PerformanceSetting.named("") == nil)
        #expect(PerformanceSetting.named("WINEDEBUG") == nil, "an env var name is not a setting key")
    }

    static let boolSettings: [PerformanceSetting] = [.metalValidation, .metalFXUpscaling, .metalHUD, .retina]

    @Test("Bool settings accept the usual spellings of true, case-insensitively",
          arguments: boolSettings, ["true", "TRUE", "on", "On", "yes", "YES", "1"])
    func boolTrueSpellings(_ setting: PerformanceSetting, _ value: String) throws {
        #expect(try setting.normalise(value) == "true")
    }

    @Test("Bool settings accept the usual spellings of false, case-insensitively",
          arguments: boolSettings, ["false", "False", "off", "OFF", "no", "No", "0"])
    func boolFalseSpellings(_ setting: PerformanceSetting, _ value: String) throws {
        #expect(try setting.normalise(value) == "false")
    }

    @Test("Bool settings reject anything that is not a boolean",
          arguments: boolSettings, ["maybe", "", "2", "truee", "-1", "enabled"])
    func boolRejectsJunk(_ setting: PerformanceSetting, _ value: String) {
        #expect(throws: CellarError.self) { try setting.normalise(value) }
    }

    @Test("wine_debug 'off' in any case, and '-all', normalise to 'off'",
          arguments: ["off", "OFF", "Off", "-all"])
    func wineDebugOff(_ value: String) throws {
        #expect(try PerformanceSetting.wineDebug.normalise(value) == "off")
    }

    @Test("wine_debug keeps a Wine channel spec verbatim",
          arguments: ["err+all,warn+crypt", "+secur32,err+all", "fixme-all", "+relay"])
    func wineDebugChannelSpec(_ value: String) throws {
        #expect(try PerformanceSetting.wineDebug.normalise(value) == value)
    }

    @Test("wine_debug rejects empty values, whitespace, quotes and '#'",
          arguments: ["", "err+all warn+crypt", "err+all\twarn", " +relay", "\"+relay", "+relay#x", "#"])
    func wineDebugRejectsUnsafe(_ value: String) {
        #expect(throws: CellarError.self) { try PerformanceSetting.wineDebug.normalise(value) }
    }

    // MARK: - resolve(): defaults

    @Test("With nothing configured, tracing is off and nothing else is touched")
    func defaultsWithNothingConfigured() throws {
        let resolved = resolve()
        #expect(resolved.env == ["WINEDEBUG": "-all"],
                "the only default effect is WINEDEBUG=-all; no Metal keys may appear")
        #expect(resolved.metalFXUpscaling == false)
        #expect(resolved.metalHUD == false)
        #expect(resolved.entries.map(\.setting) == PerformanceSetting.allCases,
                "one entry per setting, in allCases order")
        #expect(resolved.entries.allSatisfy { $0.source == .cellarDefault })
        #expect(try entry(.wineDebug, in: resolved).value == "off")
        #expect(try entry(.metalValidation, in: resolved).value == "false")
        #expect(try entry(.metalFXUpscaling, in: resolved).value == "false")
        #expect(try entry(.metalHUD, in: resolved).value == "false")
    }

    @Test("A WINEDEBUG from a profile's [env] is not overwritten by the default, and is what the entry reports")
    func profileEnvWineDebugSurvivesDefault() throws {
        let resolved = resolve(profileEnv: ["WINEDEBUG": "+secur32,err+all"])
        #expect(resolved.env["WINEDEBUG"] == "+secur32,err+all")
        let e = try entry(.wineDebug, in: resolved)
        #expect(e.value == "+secur32,err+all")
        #expect(e.source == .profile, "a raw [env] variable counts as that layer setting the switch")
    }

    // MARK: - resolve(): raw [env] variables are reported as the switch they control

    @Test("WINEDEBUG=-all in the bottle's [env] reports wine_debug off, from the bottle")
    func bottleEnvWineDebugAllIsOff() throws {
        let resolved = resolve(profileFields: ["wine_debug": "err+all"],
                               bottleEnv: ["WINEDEBUG": "-all"])
        #expect(resolved.env["WINEDEBUG"] == "-all")
        let e = try entry(.wineDebug, in: resolved)
        #expect(e.value == "off")
        #expect(e.source == .bottle)
    }

    @Test("MTL_DEBUG_LAYER in [env] reports metal_validation: '0' is false, anything else true",
          arguments: [("1", "true"), ("0", "false"), ("yes", "true")])
    func envDebugLayerReportsValidation(_ raw: String, _ expected: String) throws {
        let resolved = resolve(profileEnv: ["MTL_DEBUG_LAYER": raw])
        #expect(resolved.env["MTL_DEBUG_LAYER"] == raw, "a raw [env] value is exported untouched")
        let e = try entry(.metalValidation, in: resolved)
        #expect(e.value == expected)
        #expect(e.source == .profile)
    }

    @Test("MTL_HUD_ENABLED in [env] reports metal_hud: '0' is false, anything else true",
          arguments: [("1", "true"), ("0", "false")])
    func envHUDReportsMetalHUD(_ raw: String, _ expected: String) throws {
        let resolved = resolve(bottleEnv: ["MTL_HUD_ENABLED": raw])
        #expect(resolved.env["MTL_HUD_ENABLED"] == raw)
        let e = try entry(.metalHUD, in: resolved)
        #expect(e.value == expected)
        #expect(e.source == .bottle)
    }

    @Test("A bottle typed setting outranks the profile's [env] in the entries too")
    func bottleTypedBeatsProfileEnvInEntries() throws {
        let resolved = resolve(profileEnv: ["MTL_DEBUG_LAYER": "1", "MTL_HUD_ENABLED": "1"],
                               bottleFields: ["metal_validation": "false"])
        let validation = try entry(.metalValidation, in: resolved)
        #expect(validation.value == "false")
        #expect(validation.source == .bottle)
        let hud = try entry(.metalHUD, in: resolved)
        #expect(hud.value == "true", "the bottle said nothing about the HUD, so the profile's [env] stands")
        #expect(hud.source == .profile)
    }

    @Test("metalfx_upscaling has no env form: no [env] variable changes its entry")
    func metalFXIgnoresEnv() throws {
        let resolved = resolve(profileEnv: ["MTL_DEBUG_LAYER": "1", "MTL_HUD_ENABLED": "1",
                                            "WINEDEBUG": "+relay", "METALFX": "1"])
        let e = try entry(.metalFXUpscaling, in: resolved)
        #expect(e.value == "false")
        #expect(e.source == .cellarDefault)
        #expect(resolved.metalFXUpscaling == false)
    }

    // MARK: - resolve(): typed settings → environment

    @Test("wine_debug 'off' exports WINEDEBUG=-all; a channel spec is exported as is")
    func wineDebugToEnv() throws {
        #expect(resolve(profileFields: ["wine_debug": "off"]).env["WINEDEBUG"] == "-all")
        let spec = resolve(bottleFields: ["wine_debug": "err+all,warn+crypt"])
        #expect(spec.env["WINEDEBUG"] == "err+all,warn+crypt")
        let e = try entry(.wineDebug, in: spec)
        #expect(e.value == "err+all,warn+crypt")
        #expect(e.source == .bottle)
    }

    @Test("metal_validation true turns on the Metal debug layer with nslog error mode")
    func metalValidationOn() throws {
        let resolved = resolve(profileFields: ["metal_validation": "true"])
        #expect(resolved.env["MTL_DEBUG_LAYER"] == "1")
        #expect(resolved.env["MTL_DEBUG_LAYER_ERROR_MODE"] == "nslog")
        let e = try entry(.metalValidation, in: resolved)
        #expect(e.value == "true")
        #expect(e.source == .profile)
    }

    @Test("metal_validation false removes the debug-layer keys a profile's [env] put there")
    func metalValidationOffStripsEarlierEnv() throws {
        let resolved = resolve(profileEnv: ["MTL_DEBUG_LAYER": "1",
                                            "MTL_DEBUG_LAYER_ERROR_MODE": "nslog",
                                            "DXVK_ASYNC": "1"],
                               bottleFields: ["metal_validation": "false"])
        #expect(resolved.env["MTL_DEBUG_LAYER"] == nil)
        #expect(resolved.env["MTL_DEBUG_LAYER_ERROR_MODE"] == nil)
        #expect(resolved.env["DXVK_ASYNC"] == "1", "removing the debug layer must not take other keys with it")
        let e = try entry(.metalValidation, in: resolved)
        #expect(e.value == "false")
        #expect(e.source == .bottle)
    }

    @Test("metal_hud true sets MTL_HUD_ENABLED=1 and reports the HUD on")
    func metalHUDOn() throws {
        let resolved = resolve(bottleFields: ["metal_hud": "on"])
        #expect(resolved.env["MTL_HUD_ENABLED"] == "1")
        #expect(resolved.metalHUD == true)
        #expect(try entry(.metalHUD, in: resolved).source == .bottle)
    }

    @Test("metal_hud false removes MTL_HUD_ENABLED even when the profile's [env] set it")
    func metalHUDOffStripsEarlierEnv() throws {
        let resolved = resolve(profileEnv: ["MTL_HUD_ENABLED": "1"],
                               bottleFields: ["metal_hud": "false"])
        #expect(resolved.env["MTL_HUD_ENABLED"] == nil)
        #expect(resolved.metalHUD == false)
    }

    @Test("metalfx_upscaling is reported, and adds no environment variable of its own")
    func metalFXHasNoEnv() throws {
        let resolved = resolve(bottleFields: ["metalfx_upscaling": "yes"])
        #expect(resolved.metalFXUpscaling == true)
        #expect(resolved.env == ["WINEDEBUG": "-all"])
        let e = try entry(.metalFXUpscaling, in: resolved)
        #expect(e.value == "true")
        #expect(e.source == .bottle)
    }

    @Test("Typed values are normalised before use — 'ON' is true, '0' is false")
    func typedValuesAreNormalised() throws {
        let resolved = resolve(profileFields: ["metal_validation": "ON", "metal_hud": "1"],
                               bottleFields: ["metal_hud": "0"])
        #expect(resolved.env["MTL_DEBUG_LAYER"] == "1")
        #expect(try entry(.metalValidation, in: resolved).value == "true")
        #expect(resolved.env["MTL_HUD_ENABLED"] == nil)
        #expect(try entry(.metalHUD, in: resolved).value == "false")
    }

    @Test("Unrelated profile fields never leak into the environment")
    func unrelatedFieldsDoNotLeak() {
        let resolved = resolve(profileFields: ["name": "Planet Coaster 2", "store": "steam"])
        #expect(resolved.env == ["WINEDEBUG": "-all"])
    }

    // MARK: - resolve(): layering

    @Test("The bottle's typed setting beats the profile's typed setting")
    func bottleTypedBeatsProfileTyped() throws {
        let resolved = resolve(profileFields: ["metal_validation": "true"],
                               bottleFields: ["metal_validation": "off"])
        #expect(resolved.env["MTL_DEBUG_LAYER"] == nil)
        #expect(resolved.env["MTL_DEBUG_LAYER_ERROR_MODE"] == nil)
        #expect(try entry(.metalValidation, in: resolved).source == .bottle)
    }

    @Test("The bottle's typed setting beats the profile's raw [env]")
    func bottleTypedBeatsProfileEnv() {
        let resolved = resolve(profileEnv: ["WINEDEBUG": "+secur32,err+all"],
                               bottleFields: ["wine_debug": "off"])
        #expect(resolved.env["WINEDEBUG"] == "-all")
    }

    @Test("Within the profile, raw [env] beats the typed setting, in env and in the entries")
    func profileEnvBeatsProfileTyped() throws {
        let resolved = resolve(profileFields: ["wine_debug": "err+all", "metal_hud": "true"],
                               profileEnv: ["WINEDEBUG": "+relay", "MTL_HUD_ENABLED": "0"])
        #expect(resolved.env["WINEDEBUG"] == "+relay")
        #expect(resolved.env["MTL_HUD_ENABLED"] == "0")
        let wine = try entry(.wineDebug, in: resolved)
        #expect(wine.value == "+relay")
        #expect(wine.source == .profile)
        let hud = try entry(.metalHUD, in: resolved)
        #expect(hud.value == "false")
        #expect(hud.source == .profile)
    }

    @Test("Within the bottle, raw [env] beats the typed setting, in env and in the entries")
    func bottleEnvBeatsBottleTyped() throws {
        let resolved = resolve(bottleFields: ["metal_hud": "true", "wine_debug": "off"],
                               bottleEnv: ["MTL_HUD_ENABLED": "0", "WINEDEBUG": "warn+all"])
        #expect(resolved.env["MTL_HUD_ENABLED"] == "0")
        #expect(resolved.env["WINEDEBUG"] == "warn+all")
        let hud = try entry(.metalHUD, in: resolved)
        #expect(hud.value == "false")
        #expect(hud.source == .bottle)
        #expect(try entry(.wineDebug, in: resolved).value == "warn+all")
    }

    @Test("Profile typed setting is reported as the source when the bottle says nothing")
    func profileSourceWhenBottleSilent() throws {
        let resolved = resolve(profileFields: ["metalfx_upscaling": "true"])
        #expect(resolved.metalFXUpscaling == true)
        #expect(try entry(.metalFXUpscaling, in: resolved).source == .profile)
        #expect(try entry(.metalHUD, in: resolved).source == .cellarDefault,
                "a setting no layer touched is still the Cellar default")
    }

    @Test("Unrelated [env] keys pass through; the bottle's [env] overrides the profile's")
    func envPassThroughAndOverride() {
        let resolved = resolve(profileEnv: ["WINEDLLOVERRIDES": "mscoree=d", "DXVK_HUD": "fps"],
                               bottleEnv: ["DXVK_HUD": "full", "MY_FLAG": "1"])
        #expect(resolved.env["WINEDLLOVERRIDES"] == "mscoree=d")
        #expect(resolved.env["DXVK_HUD"] == "full")
        #expect(resolved.env["MY_FLAG"] == "1")
        #expect(resolved.env == ["WINEDLLOVERRIDES": "mscoree=d", "DXVK_HUD": "full",
                                 "MY_FLAG": "1", "WINEDEBUG": "-all"])
    }

    // MARK: - resolve(): invalid values fall through

    @Test("An invalid bottle value is ignored and the profile's choice stands")
    func invalidBottleValueFallsThrough() throws {
        let resolved = resolve(profileFields: ["metal_hud": "true"],
                               bottleFields: ["metal_hud": "maybe"])
        #expect(resolved.env["MTL_HUD_ENABLED"] == "1")
        #expect(resolved.metalHUD == true)
        let e = try entry(.metalHUD, in: resolved)
        #expect(e.source == .profile)
        #expect(e.value == "true")
    }

    @Test("An invalid value with nothing beneath it falls back to the Cellar default")
    func invalidValueFallsToDefault() throws {
        let resolved = resolve(profileFields: ["wine_debug": "err+all warn+all"],
                               bottleFields: ["metal_validation": "sometimes"])
        #expect(resolved.env == ["WINEDEBUG": "-all"])
        #expect(try entry(.wineDebug, in: resolved).source == .cellarDefault)
        #expect(try entry(.metalValidation, in: resolved).source == .cellarDefault)
        #expect(try entry(.metalValidation, in: resolved).value == "false")
    }

    // MARK: - resolve(): the Planet Coaster 2 shape

    @Test("Planet Coaster 2: the player's bottle turns off tracing and validation the profile enables")
    func planetCoaster2() throws {
        let resolved = resolve(profileFields: ["name": "Planet Coaster 2", "metal_validation": "true"],
                               profileEnv: ["WINEDEBUG": "+secur32,err+all"],
                               bottleFields: ["wine_debug": "off", "metal_validation": "false"])
        #expect(resolved.env["WINEDEBUG"] == "-all")
        #expect(resolved.env["MTL_DEBUG_LAYER"] == nil)
        #expect(resolved.env["MTL_DEBUG_LAYER_ERROR_MODE"] == nil)
        let wine = try entry(.wineDebug, in: resolved)
        #expect(wine.source == .bottle)
        #expect(wine.value == "off")
        let validation = try entry(.metalValidation, in: resolved)
        #expect(validation.source == .bottle)
        #expect(validation.value == "false")
    }

    @Test("Planet Coaster 2 without a bottle override keeps the profile's crash workaround")
    func planetCoaster2ProfileOnly() throws {
        let resolved = resolve(profileFields: ["metal_validation": "true"],
                               profileEnv: ["WINEDEBUG": "+secur32,err+all"])
        #expect(resolved.env["MTL_DEBUG_LAYER"] == "1")
        #expect(resolved.env["MTL_DEBUG_LAYER_ERROR_MODE"] == "nslog")
        #expect(resolved.env["WINEDEBUG"] == "+secur32,err+all")
        #expect(try entry(.metalValidation, in: resolved).source == .profile)
        let wine = try entry(.wineDebug, in: resolved)
        #expect(wine.value == "+secur32,err+all")
        #expect(wine.source == .profile)
    }

    // MARK: - BottleConfig: reading

    @Test("BottleConfig.env() reads only the [env] section; fields() reads scalars")
    func bottleConfigReads() throws {
        let url = try bottleFile("""
        [performance]
        metal_hud = "true"

        [env]
        DXVK_HUD = "fps"
        """)
        #expect(BottleConfig.env(url) == ["DXVK_HUD": "fps"])
        #expect(BottleConfig.fields(url)["metal_hud"] == "true")
    }

    @Test("Reading a missing bottle.toml yields empty dictionaries, not a crash")
    func bottleConfigMissingFile() throws {
        let url = try bottleFile()
        #expect(BottleConfig.fields(url).isEmpty)
        #expect(BottleConfig.env(url).isEmpty)
    }

    // MARK: - BottleConfig: set

    @Test("set() creates bottle.toml when it does not exist")
    func setCreatesFile() throws {
        let url = try bottleFile()
        try BottleConfig.set(.metalHUD, to: "on", in: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(BottleConfig.fields(url)["metal_hud"] == "true", "the stored value is normalised")
    }

    @Test("set() appends a [performance] section at the end, keeping every existing line")
    func setAppendsPerformanceSection() throws {
        let original = """
        # written by Cellar
        [bottle]
        backend = "d3dmetal"   # chosen at create time

        [env]
        DXVK_HUD = "fps"
        """
        let url = try bottleFile(original)
        try BottleConfig.set(.wineDebug, to: "OFF", in: url)

        let after = try lines(url)
        let before = original.components(separatedBy: "\n")
        #expect(Array(after.prefix(before.count)) == before, "existing lines and comments are preserved, in order")
        let header = try #require(after.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "[performance]" })
        let envHeader = try #require(after.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "[env]" })
        #expect(header > envHeader, "the new section goes at the end of the file")
        #expect(try assignments(of: "wine_debug", in: url).count == 1)
        #expect(BottleConfig.fields(url)["wine_debug"] == "off")
        #expect(BottleConfig.env(url) == ["DXVK_HUD": "fps"], "the new key must not land in [env]")
    }

    @Test("set() adds to an existing [performance] section rather than creating a second one")
    func setReusesPerformanceSection() throws {
        let url = try bottleFile("""
        [performance]
        metal_hud = "true"

        [env]
        DXVK_HUD = "fps"
        """)
        try BottleConfig.set(.metalValidation, to: "off", in: url)

        let after = try lines(url)
        #expect(after.filter { $0.trimmingCharacters(in: .whitespaces) == "[performance]" }.count == 1)
        #expect(BottleConfig.env(url) == ["DXVK_HUD": "fps"],
                "a key appended to [performance] must sit above [env], not inside it")
        #expect(BottleConfig.fields(url)["metal_validation"] == "false")
        #expect(BottleConfig.fields(url)["metal_hud"] == "true")
    }

    @Test("set() twice leaves exactly one line for the key, holding the latest value")
    func setTwiceReplaces() throws {
        let url = try bottleFile()
        try BottleConfig.set(.wineDebug, to: "err+all", in: url)
        try BottleConfig.set(.wineDebug, to: "-all", in: url)
        #expect(try assignments(of: "wine_debug", in: url).count == 1)
        #expect(BottleConfig.fields(url)["wine_debug"] == "off")
    }

    @Test("set() replaces an existing line in place, wherever it is")
    func setReplacesInPlace() throws {
        let url = try bottleFile("""
        [tuning]
        metal_hud = "false"
        other = "x"
        """)
        try BottleConfig.set(.metalHUD, to: "yes", in: url)
        let after = try lines(url)
        #expect(try assignments(of: "metal_hud", in: url).count == 1)
        #expect(BottleConfig.fields(url)["metal_hud"] == "true")
        #expect(!after.contains { $0.trimmingCharacters(in: .whitespaces) == "[performance]" },
                "an existing line is replaced, so no new section is needed")
        #expect(after.first == "[tuning]")
        #expect(BottleConfig.fields(url)["other"] == "x")
    }

    @Test("set() writes the value quoted")
    func setWritesQuoted() throws {
        let url = try bottleFile()
        try BottleConfig.set(.wineDebug, to: "err+all,warn+crypt", in: url)
        let line = try #require(try assignments(of: "wine_debug", in: url).first)
        #expect(line.contains("\"err+all,warn+crypt\""))
    }

    @Test("set() with an invalid value throws and leaves the file byte-for-byte untouched")
    func setInvalidThrowsWithoutWriting() throws {
        let original = """
        [performance]
        metal_hud = "true"
        """
        let url = try bottleFile(original)
        #expect(throws: CellarError.self) { try BottleConfig.set(.metalHUD, to: "maybe", in: url) }
        #expect(throws: CellarError.self) { try BottleConfig.set(.wineDebug, to: "a b", in: url) }
        #expect(try String(contentsOf: url, encoding: .utf8) == original)
    }

    @Test("set() with an invalid value on a missing file does not create it")
    func setInvalidDoesNotCreate() throws {
        let url = try bottleFile()
        #expect(throws: CellarError.self) { try BottleConfig.set(.wineDebug, to: "", in: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("set() leaves a commented-out line for the key alone")
    func setKeepsComments() throws {
        let url = try bottleFile("""
        # metal_hud = "true"   <- old note
        [bottle]
        backend = "d3dmetal"
        """)
        try BottleConfig.set(.metalHUD, to: "false", in: url)
        #expect(try lines(url).contains("# metal_hud = \"true\"   <- old note"))
        #expect(BottleConfig.fields(url)["metal_hud"] == "false")
    }

    @Test("Round trip: metal_validation off reads back as false and does not touch [env]")
    func roundTrip() throws {
        let url = try bottleFile("""
        [env]
        WINEDLLOVERRIDES = "mscoree=d;mshtml=d"
        """)
        let envBefore = BottleConfig.env(url)
        try BottleConfig.set(.metalValidation, to: "off", in: url)
        #expect(BottleConfig.fields(url)["metal_validation"] == "false")
        #expect(BottleConfig.env(url) == envBefore)
    }

    // MARK: - BottleConfig: unset

    @Test("unset() removes only that key's line")
    func unsetRemovesLine() throws {
        let url = try bottleFile("""
        # player choices
        [performance]
        metal_hud = "true"
        wine_debug = "off"
        """)
        try BottleConfig.unset(.metalHUD, in: url)
        #expect(BottleConfig.fields(url)["metal_hud"] == nil)
        #expect(BottleConfig.fields(url)["wine_debug"] == "off")
        let after = try lines(url)
        #expect(after.contains("# player choices"))
        #expect(after.contains("[performance]"))
    }

    @Test("unset() of an absent key changes nothing")
    func unsetAbsentKey() throws {
        let original = """
        [performance]
        wine_debug = "off"
        """
        let url = try bottleFile(original)
        try BottleConfig.unset(.metalValidation, in: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == original)
    }

    @Test("unset() on a missing file is a no-op and does not create it")
    func unsetMissingFile() throws {
        let url = try bottleFile()
        try BottleConfig.unset(.metalHUD, in: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - BottleConfig + resolve

    @Test("A setting written with BottleConfig wins over the profile when resolved")
    func bottleFileFeedsResolve() throws {
        let url = try bottleFile("""
        [env]
        MY_FLAG = "1"
        """)
        try BottleConfig.set(.metalValidation, to: "no", in: url)
        try BottleConfig.set(.metalHUD, to: "yes", in: url)

        let resolved = PerformanceSettings.resolve(
            profileFields: ["metal_validation": "true"],
            profileEnv: ["WINEDEBUG": "+secur32,err+all"],
            bottleFields: BottleConfig.fields(url),
            bottleEnv: BottleConfig.env(url))
        #expect(resolved.env["MTL_DEBUG_LAYER"] == nil)
        #expect(resolved.env["MTL_HUD_ENABLED"] == "1")
        #expect(resolved.env["MY_FLAG"] == "1")
        #expect(resolved.env["WINEDEBUG"] == "+secur32,err+all",
                "the bottle did not set wine_debug, so the profile's [env] stands")
        #expect(try entry(.metalValidation, in: resolved).source == .bottle)
        #expect(try entry(.metalHUD, in: resolved).source == .bottle)
        #expect(try entry(.wineDebug, in: resolved).source == .profile)
    }

    @Test("A bottle's WINEDLLOVERRIDES is merged with the profile's, never replaces it")
    func dllOverridesMerge() {
        let resolved = PerformanceSettings.resolve(
            profileFields: [:], profileEnv: ["WINEDLLOVERRIDES": "locationapi=d"],
            bottleFields: [:], bottleEnv: ["WINEDLLOVERRIDES": "dinput8=n,b"])
        #expect(resolved.env["WINEDLLOVERRIDES"] == "locationapi=d;dinput8=n,b")
    }

    @Test("The shipped Planet Coaster 2 profile keeps validation on, and its bottle can turn it off")
    func shippedPlanetCoaster2ThroughGamePlan() throws {
        TestHome.ensure()
        let shipped = try #require(try Repo.profileFiles().first { $0.lastPathComponent == "planet-coaster-2.toml" })
        let slug = TestHome.writeProfile(try String(contentsOf: shipped, encoding: .utf8), slug: "pc2")

        let plan = try Game.plan(slug: slug)
        #expect(plan.env["MTL_DEBUG_LAYER"] == "1")
        #expect(plan.env["WINEDEBUG"] == "-all")
        #expect(plan.metalFXUpscaling)
        #expect(try entry(.metalValidation, in: plan.performance).source == .profile)

        try BottleConfig.set(.metalValidation, to: "off", in: BottleConfig.url(forBottle: plan.bottleName))
        let tuned = try Game.plan(slug: slug)
        #expect(tuned.env["MTL_DEBUG_LAYER"] == nil)
        #expect(try entry(.metalValidation, in: tuned.performance).source == .bottle)
    }

    @Test("A hand-written switch with a trailing comment still counts")
    func handEditedSwitchWithComment() throws {
        let url = try bottleFile("""
        [performance]
        metal_validation = "false" # trying the newer D3DMetal
        """)
        #expect(BottleConfig.fields(url)["metal_validation"] == "false")
    }

    @Test("A switch's name inside [env] or [dll_overrides] is not the switch")
    func rawSectionsAreNotSwitches() throws {
        let url = try bottleFile("""
        [env]
        metal_hud = "true"

        [dll_overrides]
        wine_debug = "native"
        """)
        #expect(BottleConfig.fields(url)["metal_hud"] == nil)
        #expect(BottleConfig.fields(url)["wine_debug"] == nil)
        try BottleConfig.set(.metalHUD, to: "off", in: url)
        #expect(BottleConfig.env(url)["metal_hud"] == "true", "the [env] line is left alone")
        #expect(BottleConfig.fields(url)["metal_hud"] == "false")
    }
}
