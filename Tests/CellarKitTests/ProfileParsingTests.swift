import Foundation
import Testing
@testable import CellarKit

/// The profile TOML reader. Every fact Cellar acts on — which store, which runner, which exe —
/// comes through here, so a parsing slip is a launch failure with a confusing message.
@Suite(.serialized)
struct ProfileParsingTests {

    // MARK: - fields()

    @Test("Scalars are read across sections, quotes stripped")
    func readsScalarsAcrossSections() throws {
        let slug = TestHome.writeProfile("""
        [game]
        name  = "Planet Coaster 2"
        store = "steam"

        [launch]
        exe = "PlanetCoaster2.exe"
        """)
        let fields = ProfileStore.fields(ProfileStore.find(slug)!)
        #expect(fields["name"] == "Planet Coaster 2")
        #expect(fields["store"] == "steam")
        #expect(fields["exe"] == "PlanetCoaster2.exe")
    }

    @Test("Comment lines are ignored, including ones that contain an =")
    func ignoresComments() throws {
        let slug = TestHome.writeProfile("""
        # store = "battlenet"   <- this must not win
        [game]
        store = "gog"
        """)
        let fields = ProfileStore.fields(ProfileStore.find(slug)!)
        #expect(fields["store"] == "gog")
    }

    @Test("A trailing inline comment is stripped from the value")
    func stripsInlineComment() throws {
        let slug = TestHome.writeProfile("""
        [runner]
        id = "wineforge"   # the default
        """)
        #expect(ProfileStore.fields(ProfileStore.find(slug)!)["id"] == "wineforge")
    }

    @Test("A value containing an = keeps everything after the first one")
    func splitsOnFirstEqualsOnly() throws {
        let slug = TestHome.writeProfile("""
        [env]
        WINEDLLOVERRIDES = "mscoree=d;mshtml=d"
        """)
        let env = ProfileStore.env(ProfileStore.find(slug)!)
        #expect(env["WINEDLLOVERRIDES"] == "mscoree=d;mshtml=d")
    }

    @Test("Unrecognised keys are simply absent, not fatal")
    func unknownKeysAreAbsent() throws {
        let slug = TestHome.writeProfile("""
        [game]
        name = "X"
        """)
        #expect(ProfileStore.fields(ProfileStore.find(slug)!)["nonsense"] == nil)
    }

    // MARK: - env()

    @Test("env() reads only the [env] section")
    func envIsSectionScoped() throws {
        let slug = TestHome.writeProfile("""
        [game]
        name = "Not An Env Var"

        [env]
        MTL_HUD_ENABLED = "1"

        [install]
        method = "depot"
        """)
        let env = ProfileStore.env(ProfileStore.find(slug)!)
        #expect(env == ["MTL_HUD_ENABLED": "1"])
        #expect(env["name"] == nil)
        #expect(env["method"] == nil)
    }

    @Test("An absent [env] section yields an empty dictionary, not a crash")
    func missingEnvSection() throws {
        let slug = TestHome.writeProfile("""
        [game]
        name = "X"
        """)
        #expect(ProfileStore.env(ProfileStore.find(slug)!).isEmpty)
    }

    @Test("A commented-out env var is not exported")
    func commentedEnvVarIgnored() throws {
        let slug = TestHome.writeProfile("""
        [env]
        # MTL_HUD_ENABLED = "1"
        DXVK_HUD = "fps"
        """)
        let env = ProfileStore.env(ProfileStore.find(slug)!)
        #expect(env["MTL_HUD_ENABLED"] == nil)
        #expect(env["DXVK_HUD"] == "fps")
    }

    // MARK: - Discovery

    @Test("Profiles are discovered by slug, de-duplicated, and sorted")
    func discoveryIsSortedAndUnique() throws {
        TestHome.ensure()
        let all = ProfileStore.all()
        #expect(all.map(\.slug) == all.map(\.slug).sorted(), "profiles must list in slug order")
        #expect(Set(all.map(\.slug)).count == all.count, "a slug must appear exactly once")
    }

    @Test("A profile in the override directory outranks the one the repo ships")
    func overrideDirectoryWins() throws {
        // A player must be able to correct a shipped profile without editing Cellar. Take a slug
        // the repo really ships, shadow it, and put back whatever was there — another suite stages
        // the shipped database into this same directory.
        let slug = try #require(ProfileDatabaseTests.slugs.first)
        let url = TestHome.profilesDirectory.appendingPathComponent("\(slug).toml")
        let original = try? Data(contentsOf: url)
        defer {
            if let original { try? original.write(to: url) } else { try? FileManager.default.removeItem(at: url) }
        }

        try """
        [game]
        name = "Overridden By Test"
        store = "standalone"
        """.write(to: url, atomically: true, encoding: .utf8)

        let plan = try Game.plan(slug: slug)
        #expect(plan.name == "Overridden By Test")
        #expect(plan.store == .standalone)
    }

    @Test("An unknown slug fails with a message that names the way out")
    func unknownSlugIsActionable() throws {
        TestHome.ensure()
        #expect(throws: CellarError.self) { try Game.plan(slug: "no-such-game-\(UUID().uuidString)") }
        do {
            _ = try Game.plan(slug: "no-such-game-\(UUID().uuidString)")
        } catch let error as CellarError {
            #expect(error.description.contains("cellar profiles list"),
                    "the error must tell the player how to see what exists")
        }
    }
}
