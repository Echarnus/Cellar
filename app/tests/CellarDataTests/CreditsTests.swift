import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Whom Cellar thanks, and whether it ships what the licences ask it to.
///
/// Credits drift the moment a runner URL changes and nobody remembers the About screen. These tests
/// tie the credits to the downloads themselves, and the release scripts to the licence texts, so a
/// missing attribution fails here instead of in somebody's inbox. See `docs/LEGAL.md`.
struct CreditsTests {

    /// `github.com/<owner>/...` → `owner`, lowercased.
    private static func githubOwner(_ url: URL) -> String? {
        guard url.host == "github.com" else { return nil }
        return url.pathComponents.dropFirst().first?.lowercased()
    }

    private static var creditedOwners: Set<String> {
        Set(Credits.all.flatMap { [$0.url, $0.sourceURL].compactMap { $0 }.compactMap(githubOwner) })
    }

    @Test("Every publisher Cellar downloads a runner or tool from is credited")
    func downloadsAreCredited() throws {
        let downloads = RunnerCatalog.all.flatMap { $0.artifacts.map(\.url) } + [DepotTool.downloadURL]
        for download in downloads {
            let url = try #require(URL(string: download))
            let owner = try #require(Self.githubOwner(url), "\(download) is not on GitHub — credit it by hand and extend this test")
            // Cellar's own releases carry Cellar's builds of credited code (the patched WineForge
            // wineserver, #23); the credit belongs to the code's authors, already named.
            if owner == "echarnus" { continue }
            #expect(Self.creditedOwners.contains(owner), "\(download) comes from \(owner), whom Credits.all does not name")
        }
    }

    @Test("Every credit names its licence and says what it does")
    func creditsAreComplete() {
        let names = Credits.all.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(Credits.all.first == Credits.wine, "Wine is first: everything Cellar does happens inside it")
        for credit in Credits.all {
            #expect(!credit.role.isEmpty && !credit.license.isEmpty, "\(credit.name)")
            #expect(credit.url.scheme == "https", "\(credit.name)")
        }
    }

    // MARK: - Sources of knowledge (Kenneth, 2026-11-03: credit where credit is due)

    @Test("Every source the compatibility estimate names is credited, with its terms")
    func forecastSourcesAreCredited() {
        let names = Credits.sources.map(\.name)
        #expect(Set(names).count == names.count)
        for credit in Credits.sources {
            #expect(!credit.role.isEmpty && !credit.license.isEmpty, "\(credit.name)")
            #expect(credit.url.scheme == "https", "\(credit.name)")
        }
        // Every non-issue source a reason can carry.
        let everything = CompatibilityForecast(CompatibilitySignals(
            facts: GameFacts(graphicsAPI: "DirectX 11", anticheat: "Easy Anti-Cheat",
                             evidence: CompatibilityEvidence(protonDB: "gold", steamDeck: "verified",
                                                             anticheatOnLinux: "supported", onMac: "runs"))))
        let cited = Set(everything.reasons.compactMap(\.source).filter { !$0.hasPrefix("#") })
        #expect(cited == ["ProtonDB", "Steam Deck", "AreWeAntiCheatYet"])
        for source in cited {
            #expect(names.contains { $0.contains(source) }, "the estimate cites \(source), which Credits.sources does not name")
        }
    }

    @Test("Every address refresh-evidence.py reads belongs to a credited source")
    func refreshedSourcesAreCredited() throws {
        let script = try String(contentsOf: Repo.app.appendingPathComponent("Scripts/refresh-evidence.py"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"https://[^"\s{}()]+"#)
        let urls = regex.matches(in: script, range: NSRange(script.startIndex..., in: script))
            .compactMap { Range($0.range, in: script).map { String(script[$0]) } }
            .compactMap(URL.init(string:))
            .filter { $0.host != "github.com" }   // the script's own User-Agent names Cellar's repo
        #expect(urls.count >= 3)
        let hosts = Set(Credits.sources.flatMap { [$0.url, $0.sourceURL].compactMap { $0?.host } })
        let owners = Set(Credits.sources.flatMap { [$0.url, $0.sourceURL].compactMap { $0 }.compactMap(Self.githubOwner) })
        for url in urls {
            let rawOwner = url.host == "raw.githubusercontent.com" ? url.pathComponents.dropFirst().first?.lowercased() : nil
            let credited = hosts.contains(url.host ?? "") || rawOwner.map { owners.contains($0) } == true
            #expect(credited, "refresh-evidence.py reads \(url), and no credit in Credits.sources covers it")
        }
    }

    @Test("Every public source a shipped profile cites is credited")
    func profileSourcesAreCredited() throws {
        // The sources profiles cite by name. A profile citing a new one adds it here and to
        // Credits.sources together.
        let cited = ["ProtonDB", "AppleGamingWiki", "CodeWeavers", "PCGamingWiki", "SteamDB", "AreWeAntiCheatYet"]
        let names = Credits.sources.map(\.name)
        for source in cited {
            #expect(names.contains { $0.contains(source) }, "\(source) is cited in profiles but not credited")
        }
    }

    /// Every package in Package.resolved, with the Credit and the licence text that cover it. A new
    /// package fails this until it has a Credit, a row in THIRD_PARTY_LICENSES.md and a text in
    /// licenses/ — and a line here.
    private static let dependencies: [(identity: String, credit: String, text: String)] = [
        ("sparkle", "Sparkle", "Sparkle.txt"),
        ("swift-argument-parser", "swift-argument-parser", "swift-argument-parser.txt"),
    ]

    @Test("Every compiled-in or bundled dependency is credited and its licence text ships")
    func dependenciesAreCovered() throws {
        let resolved = try String(contentsOf: Repo.app.appendingPathComponent("Package.resolved"), encoding: .utf8)
        let identities = resolved.components(separatedBy: "\"identity\" : \"").dropFirst()
            .compactMap { $0.split(separator: "\"").first.map(String.init) }
        #expect(Set(identities) == Set(Self.dependencies.map(\.identity)),
                "a dependency was added or removed: give it a Credit, a row in THIRD_PARTY_LICENSES.md and a text in licenses/")
        let inventory = try String(contentsOf: Repo.root.appendingPathComponent("THIRD_PARTY_LICENSES.md"), encoding: .utf8)
        for dependency in Self.dependencies {
            #expect(Credits.all.contains { $0.name == dependency.credit }, "\(dependency.credit) has no Credit")
            #expect(inventory.contains(dependency.credit), "\(dependency.credit) is not in THIRD_PARTY_LICENSES.md")
            let text = Repo.root.appendingPathComponent("licenses/\(dependency.text)")
            #expect(FileManager.default.fileExists(atPath: text.path), "licenses/\(dependency.text) is missing")
        }
    }

    @Test("Every release artifact carries the licence and notices", arguments: ["package.sh", "install-app.sh"])
    func releaseShipsLegal(_ script: String) throws {
        let body = try String(contentsOf: Repo.app.appendingPathComponent("Scripts/\(script)"), encoding: .utf8)
        for item in ["LICENSE", "NOTICE", "THIRD_PARTY_LICENSES.md", "licenses"] {
            #expect(body.contains(item), "\(script) does not copy \(item) into the release")
        }
    }

    @Test("The DMG carries the licence and notices, in a folder in the install window")
    func dmgShipsLicence() throws {
        let body = try String(contentsOf: Repo.app.appendingPathComponent("Scripts/make-dmg.sh"), encoding: .utf8)
        #expect(body.contains("cp ../LICENSE"))  // the licence sits at the checkout root, beside app/
        #expect(body.contains("cp ../NOTICE"))
        // …and the folder they are in is one of the three things laid out in the window.
        #expect(body.contains("set position of item \"Licence and Read Me\""))
    }
}
