import Foundation
import Testing
@testable import CellarKit

/// Tier A: Cellar only runs games installed through a store. These run the real profile database
/// and a storeless profile through discovery, planning and the library together, on real files —
/// the unit suite proves `Game.plan` refuses one; this proves the refusal holds end to end.
@Suite(.serialized)
struct StoreRuleTests {

    @Test("Every shipped profile names a store Cellar supports, and plans through it")
    func shippedProfilesAllNameAStore() throws {
        #expect(IT.shippedProfilesStaged)
        let shipped = try FileManager.default
            .contentsOfDirectory(at: IT.shippedProfilesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "toml" }
        #expect(!shipped.isEmpty)
        for url in shipped {
            let slug = url.deletingPathExtension().lastPathComponent
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.range(of: #"(?m)^\s*store\s*=\s*"(steam|battlenet|gog)""#,
                               options: .regularExpression) != nil,
                    "\(slug).toml must spell out its store")
            do { _ = try Game.plan(slug: slug) } catch { Issue.record("\(slug) must plan: \(error)") }
        }
    }

    @Test("A storeless profile is found on disk but never planned, listed or launched")
    func storelessProfileNeverReachesThePlayer() throws {
        IT.ensure()
        let slug = IT.writeProfile("""
        [game]
        name = "Downloaded By Hand"
        [launch]
        exe = "Game.exe"
        """, slug: "it-storeless")

        #expect(ProfileStore.find(slug) != nil, "the file is there…")
        #expect(throws: CellarError.self, "…but planning it is refused") { _ = try Game.plan(slug: slug) }
        #expect(Game.summaries().contains { $0.slug == slug } == false, "…and the library never shows it")
        for store in GameStore.allCases {
            #expect(Game.bottleNames(forStore: store).contains(slug) == false,
                    "no store claims a bottle for it either")
        }
    }
}
