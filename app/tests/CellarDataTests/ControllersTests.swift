import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// What Cellar says about game controllers: the pad's family, and what the profile recorded.
@Suite(.serialized)
struct ControllersTests {

    @Test("A pad's family is read from macOS's product category")
    func kinds() {
        #expect(Controllers.Kind(productCategory: "Xbox One") == .xbox)
        #expect(Controllers.Kind(productCategory: "Xbox Series X") == .xbox)
        #expect(Controllers.Kind(productCategory: "DualSense") == .dualSense)
        #expect(Controllers.Kind(productCategory: "DualShock 4") == .dualShock)
        #expect(Controllers.Kind(productCategory: "Switch Pro Controller") == .switchPro)
        #expect(Controllers.Kind(productCategory: "MFi") == .other)
    }

    @Test("A profile's controller field is shown in words, and no field shows nothing")
    func support() throws {
        #expect(Controllers.support("full") == "Full controller support")
        #expect(Controllers.support(" Partial ")?.hasPrefix("Partial") == true)
        #expect(Controllers.support("none") == "Keyboard and mouse only")
        #expect(Controllers.support(nil) == nil)
        #expect(Controllers.support("") == nil)

        TestHome.ensure()
        let slug = TestHome.writeProfile("""
        [game]
        name = "Pad Fixture"
        store = "gog"

        [compatibility]
        controller = "full"
        """, slug: "pad")
        let facts = try Game.plan(slug: slug).facts
        #expect(facts.controller == "full")
        #expect(facts.compatibility.contains { $0.label == "Controller" && $0.value == "Full controller support" })
    }

    @Test("Steam Input is mentioned only when Steam's client starts the game")
    func steamInput() {
        #expect(Controllers.steamInputNote(store: .steam, throughClient: true) != nil)
        #expect(Controllers.steamInputNote(store: .steam, throughClient: false) == nil)
        #expect(Controllers.steamInputNote(store: .gog, throughClient: true) == nil)
    }
}
