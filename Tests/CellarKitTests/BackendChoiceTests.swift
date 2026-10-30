import Foundation
import Testing
@testable import CellarKit

/// The profile's second graphics backend, offered when the first one doesn't bring a game up, and
/// the player's switch to it kept in the bottle.
@Suite(.serialized)
struct BackendChoiceTests {

    @Test("A profile's fallback_backend reaches the plan, and the bottle's choice beats the profile")
    func planCarriesFallbackAndChoice() throws {
        TestHome.ensure()
        let slug = TestHome.writeProfile("""
        [game]
        name = "Backend Fixture"
        store = "steam"
        steam_appid = "480"

        [graphics]
        backend = "d3dmetal"
        fallback_backend = "dxvk"
        """, slug: "backend")
        let plan = try Game.plan(slug: slug)
        #expect(plan.backend == "d3dmetal")
        #expect(plan.profileBackend == "d3dmetal")
        #expect(plan.fallbackBackend == "dxvk")
        #expect(plan.retryBackend == .dxvk)

        let file = BottleConfig.url(forBottle: plan.bottleName)
        try BackendChoice.set(.dxvk, in: file)
        defer { try? BackendChoice.set(nil, in: file) }
        let chosen = try Game.plan(slug: slug)
        #expect(chosen.backend == "dxvk")
        #expect(chosen.graphicsBackend == .dxvk)
        #expect(chosen.profileBackend == "d3dmetal", "the profile's own backend stays known, for the way back")
        #expect(chosen.retryBackend == nil, "already on the fallback: nothing further to offer")

        try BackendChoice.set(nil, in: file)
        #expect(try Game.plan(slug: slug).backend == "d3dmetal")
    }

    @Test("The bottle's day-one backend line is not read as the player's choice")
    func creationLineIsNotAChoice() throws {
        let url = TestHome.scratch("bottle").appendingPathComponent("bottle.toml")
        try "backend = \"dxmt\"\nrunner = \"wineforge\"\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(BackendChoice.chosen(in: url) == nil)
        try BackendChoice.set(.dxvk, in: url)
        #expect(BackendChoice.chosen(in: url) == .dxvk)
        #expect(BottleConfig.fields(url)["backend"] == "dxmt", "the creation record is left alone")
        try BackendChoice.set(.dxmt, in: url)
        #expect(try String(contentsOf: url, encoding: .utf8).components(separatedBy: "graphics_backend =").count == 2,
                "changing the choice rewrites its line, never adds a second")
    }

    @Test("The fallback is offered once, never in a loop")
    func retryIsOfferedOnce() {
        let cases: [(current: String, primary: String, fallback: String?, expected: GraphicsBackend?)] = [
            ("d3dmetal", "d3dmetal", "dxvk", .dxvk),        // on the primary: offer it
            ("dxvk", "d3dmetal", "dxvk", nil),              // already switched
            ("d3dmetal", "d3dmetal", nil, nil),             // profile names none
            ("d3dmetal", "d3dmetal", "d3dmetal", nil),      // fallback is the primary
            ("dxmt", "d3dmetal", "dxvk", nil),              // player picked a third
            ("d3dmetal", "d3dmetal", "metal-magic", nil),   // unknown id
        ]
        for c in cases {
            #expect(BackendChoice.retry(current: c.current, primary: c.primary, fallback: c.fallback) == c.expected,
                    "\(c.current) / \(c.primary) / \(c.fallback ?? "none")")
        }
    }

    @Test("Every shipped profile's backend and fallback are backends Cellar knows")
    func shippedBackendsAreKnown() throws {
        for slug in ProfileDatabaseTests.slugs {
            let plan = try Game.plan(slug: slug)
            #expect(GraphicsBackend(rawValue: plan.profileBackend) != nil, "\(slug): backend = \(plan.profileBackend)")
            if let fallback = plan.fallbackBackend {
                #expect(GraphicsBackend(rawValue: fallback) != nil, "\(slug): fallback_backend = \(fallback)")
            }
        }
    }

    @Test("A backend can be named by id or by its own name")
    func naming() {
        #expect(GraphicsBackend(named: "DXVK") == .dxvk)
        #expect(GraphicsBackend(named: "d3dmetal") == .d3dmetal)
        #expect(GraphicsBackend(named: "VKD3D-Proton") == .vkd3d)
        #expect(GraphicsBackend(named: "opengl") == nil)
    }
}
