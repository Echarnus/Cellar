import Foundation
import Testing
@testable import CellarKit

/// Tier A: what Cellar says about game controllers, through the same paths `cellar doctor` and the
/// library use — real GameController discovery, a real profile on disk, the real summaries.
@Suite(.serialized)
struct ControllerTests {

    @Test("`cellar doctor` reports controllers as information, and agrees with discovery")
    func doctorReportsControllers() {
        let pads = Controllers.connected(settle: 0.5)
        let check = SystemEnvironment.diagnostics().first { $0.name == "Controllers" }
        #expect(check != nil, "doctor must always say something about controllers")
        #expect(check?.status == .info, "a pad macOS sees is not proof a game takes it — never a ✓")
        if pads.isEmpty {
            // CI runners have no pads: the honest answer is "none", with no hint promising more.
            #expect(check?.detail == "none connected")
            #expect(check?.hint == nil)
        } else {
            for pad in pads { #expect(check?.detail.contains(pad.name) == true) }
        }
    }

    @Test("A profile's controller answer reaches the library, and no answer shows nothing")
    func controllerFactReachesTheLibrary() throws {
        IT.ensure()
        let recorded = IT.writeProfile("""
        [game]
        name = "Pad Game"
        store = "gog"
        [compatibility]
        controller = "partial"
        """, slug: "it-pad")
        let silent = IT.writeProfile("""
        [game]
        name = "Quiet Game"
        store = "gog"
        """, slug: "it-nopad")

        let summaries = Game.summaries()
        let withPad = try #require(summaries.first { $0.slug == recorded })
        #expect(withPad.facts.compatibility.contains {
            $0.label == "Controller" && $0.value.hasPrefix("Partial")
        })
        let without = try #require(summaries.first { $0.slug == silent })
        #expect(without.facts.compatibility.contains { $0.label == "Controller" } == false,
                "an unrecorded answer is not a guess")
    }
}
