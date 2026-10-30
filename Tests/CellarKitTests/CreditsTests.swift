import Foundation
import Testing
@testable import CellarKit

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

    @Test("The one compiled-in dependency is credited and its licence text ships")
    func compiledDependencyIsCovered() throws {
        let resolved = try String(contentsOf: Repo.root.appendingPathComponent("Package.resolved"), encoding: .utf8)
        #expect(resolved.contains("swift-argument-parser"))
        // A new package in Package.resolved means a new licence text in licenses/ and a new Credit.
        let identities = resolved.components(separatedBy: "\"identity\"").count - 1
        #expect(identities == 1, "a dependency was added: give it a Credit, a row in THIRD_PARTY_LICENSES.md and a text in licenses/")
        #expect(Credits.all.contains { $0.name == "swift-argument-parser" })
        let text = Repo.root.appendingPathComponent("licenses/swift-argument-parser.txt")
        #expect(FileManager.default.fileExists(atPath: text.path))
    }

    @Test("Every release artifact carries the licence and notices", arguments: ["package.sh", "install-app.sh"])
    func releaseShipsLegal(_ script: String) throws {
        let body = try String(contentsOf: Repo.root.appendingPathComponent("Scripts/\(script)"), encoding: .utf8)
        for item in ["LICENSE", "NOTICE", "THIRD_PARTY_LICENSES.md", "licenses"] {
            #expect(body.contains(item), "\(script) does not copy \(item) into the release")
        }
    }

    @Test("The DMG carries the licence at the top level")
    func dmgShipsLicence() throws {
        let body = try String(contentsOf: Repo.root.appendingPathComponent("Scripts/make-dmg.sh"), encoding: .utf8)
        #expect(body.contains("cp LICENSE"))
        #expect(body.contains("cp NOTICE"))
    }
}
