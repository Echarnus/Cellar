import CellarData
import CellarDomain
import Testing

/// `CELLAR_SHOWCASE=1`: the website's captures show "Cellar", never the player's own account.
@Suite("Showcase display override")
struct ShowcaseTests {
    @Test("Only CELLAR_SHOWCASE=1 turns it on")
    func switchedByTheVariable() {
        #expect(Showcase.isOn(["CELLAR_SHOWCASE": "1"]))
        #expect(!Showcase.isOn([:]))
        #expect(!Showcase.isOn(["CELLAR_SHOWCASE": "0"]))
    }

    @Test("A Steam sign-in keeps its state and age but is named Cellar")
    func steamNameReplaced() {
        #expect(Showcase.masking(.signedIn(account: "kennethdc", days: 4, aging: true))
                == .signedIn(account: "Cellar", days: 4, aging: true))
        #expect(Showcase.masking(.expired(account: "kennethdc", reason: "revoked"))
                == .expired(account: "Cellar", reason: "revoked"))
        #expect(Showcase.masking(SteamSignInState.signedOut) == .signedOut)
    }

    @Test("The account button and the Accounts sentence never carry the real name")
    func nothingLeaks() {
        let steam = Showcase.masking(.signedIn(account: "kennethdc", days: 1, aging: false))
        let summary = AccountSummary(connected: [.steam], steam: steam, offered: [.steam])
        #expect(summary.title == "Cellar")
        #expect(!steam.summary.contains("kennethdc"))
        #expect(Showcase.masking("kennethdc") == "Cellar")
        #expect(Showcase.masking(nil as String?) == nil)
    }
}
