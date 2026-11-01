import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// A profile's crash workaround, switched off by the player, and the launch that puts it back.
///
/// Planet Coaster 2's profile turns Metal validation on because without it D3DMetal 3.0 kills the
/// game seconds after it starts. On 2026-11-01 a bottle with validation switched off in the app
/// crashed six starts in a row, and the launch kept retrying the same crash until the player gave
/// up. These pin the way out: the plan knows which workaround the player switched off and what the
/// game's environment is with it back on, a launch that dies as it starts switches over once, and
/// the bottle only gives the profile its say back when the game then stayed up.
@Suite(.serialized)
struct CrashWorkaroundTests {

    private static let profile = """
    [game]
    name = "Workaround Fixture"
    store = "steam"
    steam_appid = "480"
    exe = "Fixture.exe"

    [runner]
    metal_validation = true
    metal_hud = false
    """

    private func plan(bottle: String?) throws -> GamePlan {
        TestHome.ensure()
        let slug = TestHome.writeProfile(Self.profile, slug: "workaround")
        let first = try Game.plan(slug: slug)
        if let bottle {
            let file = BottleConfig.url(forBottle: first.bottleName)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bottle.write(to: file, atomically: true, encoding: .utf8)
        }
        return try Game.plan(slug: slug)
    }

    // MARK: - Which switches count

    @Test("Metal validation is the crash workaround; the switches a player picks for taste are not")
    func onlyValidationIsAWorkaround() {
        #expect(PerformanceSetting.metalValidation.isCrashWorkaround)
        for setting in PerformanceSetting.allCases where setting != .metalValidation {
            #expect(!setting.isCrashWorkaround, "\(setting.key) is taste, not a crash fix")
        }
    }

    @Test("Switched off is when the profile turns it on and the bottle turns it off — nothing else")
    func switchedOffNeedsBothLayers() {
        func off(_ profile: [String: String], _ profileEnv: [String: String] = [:],
                 _ bottle: [String: String]) -> [PerformanceSetting] {
            PerformanceSettings.resolve(profileFields: profile, profileEnv: profileEnv,
                                        bottleFields: bottle, bottleEnv: [:]).crashWorkaroundsSwitchedOff
        }
        #expect(off(["metal_validation": "true"], ["metal_validation": "false"]) == [.metalValidation])
        #expect(off(["metal_validation": "true"], ["metal_validation": "off"]) == [.metalValidation],
                "every spelling the CLI accepts counts")
        #expect(off([:], ["MTL_DEBUG_LAYER": "1"], ["metal_validation": "false"]) == [.metalValidation],
                "a profile that turns the layer on through [env] is turning the same switch on")
        #expect(off(["metal_validation": "true"], [:]).isEmpty, "the profile's own choice stands")
        #expect(off(["metal_validation": "true"], ["metal_validation": "true"]).isEmpty)
        #expect(off([:], ["metal_validation": "false"]).isEmpty,
                "a game whose profile never needed it has nothing to put back")
        #expect(off(["metal_hud": "true"], ["metal_hud": "false"]).isEmpty, "the frame-rate overlay is taste")
    }

    @Test("The profile's workarounds are known whatever the bottle says, for the warning beside the switch")
    func workaroundsInProfile() {
        let resolved = PerformanceSettings.resolve(profileFields: ["metal_validation": "true"], profileEnv: [:],
                                                   bottleFields: ["metal_validation": "false"], bottleEnv: [:])
        #expect(resolved.crashWorkaroundsInProfile == [.metalValidation])
        let none = PerformanceSettings.resolve(profileFields: [:], profileEnv: [:], bottleFields: [:], bottleEnv: [:])
        #expect(none.crashWorkaroundsInProfile.isEmpty)
    }

    // MARK: - The plan

    @Test("A bottle that switched validation off launches without it, and the plan holds the environment with it")
    func planCarriesBothEnvironments() throws {
        let plan = try plan(bottle: "[performance]\nmetal_validation = \"false\"\nmetal_hud = \"true\"\n")
        #expect(plan.launchEnv["MTL_DEBUG_LAYER"] == nil, "the player's choice is what the first start gets")
        #expect(plan.crashWorkaroundsSwitchedOff == [.metalValidation])

        let restored = try #require(plan.launchEnvWithWorkarounds)
        #expect(restored["MTL_DEBUG_LAYER"] == "1")
        #expect(restored["MTL_HUD_ENABLED"] == "1", "only the workaround goes back: the player's overlay stays on")
        var rest = restored
        rest["MTL_DEBUG_LAYER"] = nil
        rest["MTL_DEBUG_LAYER_ERROR_MODE"] = nil
        #expect(rest == plan.launchEnv, "the rest of the launch environment is the same launch's")

        let workaround = try #require(plan.launchWorkaround)
        #expect(workaround.message.contains("Workaround Fixture"))
        #expect(workaround.message.contains("Metal validation"), "the player reads the switch's own name")
        #expect(workaround.message.contains("turning it back on"))
    }

    @Test("Nothing to put back when the player left the workaround alone")
    func nothingToRestore() throws {
        #expect(try plan(bottle: nil).launchWorkaround == nil)
        #expect(try plan(bottle: "[performance]\nmetal_hud = \"true\"\n").launchWorkaround == nil)
        #expect(try plan(bottle: "[performance]\nmetal_validation = \"true\"\n").launchWorkaround == nil)
    }

    @Test("Keeping the workaround removes only the bottle's override, and the next plan reads the profile's choice")
    func keepingRestoresTheProfile() throws {
        let plan = try plan(bottle: "# mine\n[performance]\nmetal_validation = \"false\"\nmetal_hud = \"true\"\n")
        try #require(plan.launchWorkaround).keep()

        let text = try String(contentsOf: BottleConfig.url(forBottle: plan.bottleName), encoding: .utf8)
        #expect(!text.contains("metal_validation"))
        #expect(text.contains("metal_hud = \"true\""), "the player's other choices are untouched")
        #expect(text.contains("# mine"))

        let next = try Game.plan(slug: plan.slug)
        let entry = try #require(next.performance.entries.first { $0.setting == .metalValidation })
        #expect(entry.value == "true")
        #expect(entry.source == .profile)
        #expect(next.launchEnv["MTL_DEBUG_LAYER"] == "1", "the next Play starts with it on")
        #expect(next.launchWorkaround == nil)
    }

    // MARK: - The launch

    /// A game that dies within the settle window unless the environment it was started with has the
    /// validation layer on — what Planet Coaster 2 did on Kenneth's Mac.
    private func supervise(workaround: LaunchWorkaround?, attempts: Int = 4,
                           lines: inout [String]) throws -> [[String: String]] {
        let fallback = LaunchWorkaroundSwitch(workaround)
        var env: [String: String] = ["MTL_HUD_ENABLED": "1"]
        var started: [[String: String]] = []
        var checks = 0
        var collected: [String] = []
        defer { lines = collected }
        try ProcessWatch.superviseStart(
            attempts: attempts, appearSeconds: 1, settleSeconds: 1, backoffSeconds: 0,
            cleanup: {},
            start: { started.append(env); checks = 0 },
            isUp: {
                checks += 1
                return started.last?["MTL_DEBUG_LAYER"] == "1" || checks == 1
            },
            diedStarting: { _ in
                if let restored = fallback.diedStarting(progress: { collected.append($0) }) { env = restored }
            },
            progress: { collected.append($0) })
        fallback.stayedUp()
        return started
    }

    @Test("A start that dies with the workaround off is retried once with it on, and that is kept")
    func diesThenStaysUpWithTheWorkaround() throws {
        var kept = 0
        let workaround = LaunchWorkaround(env: ["MTL_HUD_ENABLED": "1", "MTL_DEBUG_LAYER": "1"],
                                          message: "Fixture crashed as it started with Metal validation off.",
                                          keep: { kept += 1 })
        var lines: [String] = []
        let started = try supervise(workaround: workaround, lines: &lines)

        #expect(started.count == 2, "one crash, then up — not eight crashes and a give-up")
        #expect(started[0]["MTL_DEBUG_LAYER"] == nil)
        #expect(started[1]["MTL_DEBUG_LAYER"] == "1")
        #expect(started[1]["MTL_HUD_ENABLED"] == "1")
        #expect(kept == 1, "a workaround that worked becomes the bottle's setting again")
        #expect(lines.contains("Fixture crashed as it started with Metal validation off."),
                "the player is told what Cellar changed")
    }

    @Test("A workaround that doesn't help is not kept, and the launch still fails honestly")
    func aWorkaroundThatDoesNotHelpIsNotKept() {
        var kept = 0
        let fallback = LaunchWorkaroundSwitch(LaunchWorkaround(env: ["MTL_DEBUG_LAYER": "1"], message: "m",
                                                               keep: { kept += 1 }))
        var switches = 0
        var checks = 0
        #expect(throws: CellarError.self) {
            // Appears, then dies, every time — with the workaround on too.
            try ProcessWatch.superviseStart(
                attempts: 3, appearSeconds: 1, settleSeconds: 1, backoffSeconds: 0,
                cleanup: {}, start: { checks = 0 }, isUp: { checks += 1; return checks == 1 },
                diedStarting: { _ in if fallback.diedStarting(progress: { _ in }) != nil { switches += 1 } })
            fallback.stayedUp()
        }
        #expect(switches == 1)
        #expect(kept == 0, "the player's choice stays theirs when putting the workaround back didn't help")
    }

    @Test("The switch happens once, and never after the last attempt")
    func switchesOnce() {
        var deaths: [Int] = []
        var checks = 0
        #expect(throws: CellarError.self) {
            try ProcessWatch.superviseStart(
                attempts: 3, appearSeconds: 1, settleSeconds: 1, backoffSeconds: 0,
                cleanup: {}, start: { checks = 0 }, isUp: { checks += 1; return checks == 1 },
                diedStarting: { deaths.append($0) })
        }
        #expect(deaths == [1, 2], "told after every death that has an attempt after it")

        let fallback = LaunchWorkaroundSwitch(LaunchWorkaround(env: ["A": "1"], message: "m", keep: {}))
        #expect(fallback.diedStarting(progress: { _ in }) == ["A": "1"])
        #expect(fallback.diedStarting(progress: { _ in }) == nil, "already on: a retry is all that is left")
        #expect(LaunchWorkaroundSwitch(nil).diedStarting(progress: { _ in }) == nil)
    }

    @Test("Without a workaround the launch retries as before")
    func noWorkaroundRetriesAsBefore() throws {
        var lines: [String] = []
        // Dies on every start, never switches, gives up after the attempts.
        #expect(throws: CellarError.self) { _ = try supervise(workaround: nil, attempts: 2, lines: &lines) }
        #expect(!lines.contains { $0.contains("turning it back on") })
    }
}
