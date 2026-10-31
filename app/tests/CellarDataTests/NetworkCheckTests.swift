import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// `cellar network`. The probe itself needs Wine and the internet — the behaviour rung — so these
/// pin down what can be checked headless: reading the probe's output, naming each failure, and
/// the verdict that says whose problem it is.
struct NetworkCheckTests {

    @Test("The probe's lines read back into outcomes; a mangled line is skipped, not guessed")
    func parsesProbeOutput() {
        let text = """
        https://a.example/\tok 200
        https://b.example/\terror 12007
        https://c.example/\terror 12175
        https://d.example/\tok 404
        https://e.example/\tsomething else
        garbage
        """
        let outcomes = NetworkCheck.parseProbeOutput(text)
        #expect(outcomes["https://a.example/"] == .reached(status: 200))
        #expect(outcomes["https://b.example/"] == .nameNotResolved)
        #expect(outcomes["https://c.example/"] == .secureConnectionFailed)
        #expect(outcomes["https://d.example/"] == .reached(status: 404), "any HTTP answer proves DNS, TCP and TLS worked")
        #expect(outcomes["https://e.example/"] == nil)
        #expect(outcomes.count == 4)
    }

    @Test("WinHTTP's error codes land in the layer they come from",
          arguments: [(12007, NetworkCheck.Outcome.nameNotResolved),
                      (12029, .cannotConnect),
                      (12002, .timedOut),
                      (12175, .secureConnectionFailed),
                      (12157, .secureConnectionFailed),
                      (12045, .certificateRejected),
                      (12038, .certificateRejected),
                      (12345, .other(code: 12345))])
    func classifiesWinHTTPErrors(_ code: Int, _ expected: NetworkCheck.Outcome) {
        #expect(NetworkCheck.Outcome(winHTTPError: code) == expected)
    }

    @Test("Only the bottle failing is the layer's fault, and the verdict says so")
    func blamesTheLayerOnlyWhenTheMacGetsThrough() {
        let layer = NetworkCheck.Result(url: "https://www.frontierstore.net/", mac: .reached(status: 200),
                                        bottle: .certificateRejected)
        #expect(layer.layerIsInTheWay)
        let verdict = NetworkCheck.verdict([layer])
        #expect(verdict.contains("www.frontierstore.net"))
        #expect(verdict.contains("Cellar's to fix"))
        #expect(verdict.contains("certificate"))
    }

    @Test("When the Mac can't get through either, the player is pointed at the connection, not Cellar")
    func blamesTheConnectionWhenBothFail() {
        let both = NetworkCheck.Result(url: "https://steamcommunity.com/", mac: .cannotConnect, bottle: .cannotConnect)
        #expect(!both.layerIsInTheWay)
        let verdict = NetworkCheck.verdict([both])
        #expect(verdict.contains("from this Mac either"))
        #expect(!verdict.contains("Cellar's to fix"))
    }

    @Test("An open path says the layer is not the place to look")
    func clearsTheLayerWhenEverythingIsReached() {
        let ok = NetworkCheck.Result(url: "https://steamcommunity.com/", mac: .reached(status: 200), bottle: .reached(status: 200))
        #expect(NetworkCheck.verdict([ok]).contains("not the layer"))
    }

    @Test("The store's services come first, the profile's follow, without repeats or non-URLs")
    func mergesStoreAndProfileURLs() {
        let urls = NetworkCheck.urls(store: .steam,
                                     profileValue: "https://www.frontierstore.net/ steamcommunity.com https://steamcommunity.com/")
        #expect(urls == ["https://api.steampowered.com/", "https://steamcommunity.com/", "https://www.frontierstore.net/"])
    }

    @Test("Planet Coaster 2 checks Frontier's services, not just Steam's")
    func planetCoasterChecksFrontier() {
        let ref = ProfileRef(slug: "planet-coaster-2", url: Repo.profiles.appendingPathComponent("planet-coaster-2.toml"))
        let urls = NetworkCheck.urls(store: .steam, profileValue: ProfileStore.fields(ref)["network_check"])
        #expect(urls.contains { URL(string: $0)?.host?.hasSuffix("frontierstore.net") == true })
    }

    @Test("The in-bottle probe uses WinHTTP — the stack the game itself goes through")
    func probeUsesWinHTTP() {
        #expect(NetworkCheck.probeScript.contains("WinHttp.WinHttpRequest.5.1"))
        #expect(NetworkCheck.probeScript.contains("args.Item(0)"), "results go to a file, not WScript.Echo")
    }
}
