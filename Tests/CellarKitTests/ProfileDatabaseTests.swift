import Foundation
import Testing
@testable import CellarKit

/// A lint over the profile database the repo actually ships.
///
/// A profile is the whole contract for a game: get a field wrong and the failure surfaces to a
/// player as "it doesn't work", with no clue why. The app also shows these facts *verbatim*, so
/// `status` and `notes` are not decoration — an untested profile that doesn't say so is a lie the
/// interface tells on Cellar's behalf.
@Suite(.serialized)
struct ProfileDatabaseTests {

    /// The repo's `profiles/` directory, found from this file rather than the working directory.
    static let directory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // CellarKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // <repo>
        .appendingPathComponent("profiles", isDirectory: true)

    /// Every shipped profile, staged where `ProfileStore` will find it.
    static let slugs: [String] = {
        TestHome.ensure()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        var staged: [String] = []
        for url in entries where url.pathExtension == "toml" {
            let target = TestHome.profilesDirectory.appendingPathComponent(url.lastPathComponent)
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: url, to: target)
            staged.append(url.deletingPathExtension().lastPathComponent)
        }
        return staged.sorted()
    }()

    @Test("The database is not empty and every file is a readable profile")
    func databaseLoads() throws {
        #expect(!Self.slugs.isEmpty, "profiles/ has no .toml files — Cellar would ship no games")
        for slug in Self.slugs {
            #expect(throws: Never.self) { try Game.plan(slug: slug) }
        }
    }

    @Test("Every profile resolves into a usable plan", arguments: ProfileDatabaseTests.slugs)
    func planIsUsable(_ slug: String) throws {
        let plan = try Game.plan(slug: slug)

        #expect(!plan.name.isEmpty)
        #expect(plan.name != slug, "profile '\(slug)' has no display name")
        #expect(!plan.bottleName.isEmpty)
        #expect(RunnerCatalog.spec(forID: plan.runnerID) != nil,
                "'\(slug)' pins runner '\(plan.runnerID)', which is not in the catalog")
        #expect(GraphicsBackend(rawValue: plan.backend) != nil,
                "'\(slug)' names backend '\(plan.backend)', which is not a backend Cellar has")
    }

    @Test("Each profile carries what its store needs to install and launch",
          arguments: ProfileDatabaseTests.slugs)
    func storeRequirements(_ slug: String) throws {
        let plan = try Game.plan(slug: slug)
        switch plan.store {
        case .steam:
            #expect(plan.appID != nil, "'\(slug)' is a Steam game with no steam_appid — nothing can launch it")
            #expect((plan.appID ?? 0) > 0)
        case .battlenet:
            #expect(plan.productCode != nil,
                    "'\(slug)' is a Battle.net game with no product_code — the client cannot be told what to start")
            #expect(!plan.gameProcessNeedles.isEmpty,
                    "'\(slug)' needs an exe or install_dir, or Cellar cannot tell when the game is running")
        case .gog:
            #expect(plan.gogProductID != nil, "'\(slug)' is a GOG game with no gog_product_id")
            #expect(plan.launchExe != nil, "a GOG game is launched directly, so it needs an exe")
        case .standalone:
            #expect(plan.launchExe != nil, "'\(slug)' has no store and no exe — there is nothing to run")
        }
    }

    @Test("A profile that does not need a live session says how to start the game itself",
          arguments: ProfileDatabaseTests.slugs)
    func drmFreeGamesAreLaunchable(_ slug: String) throws {
        let plan = try Game.plan(slug: slug)
        if !plan.needsLiveSession {
            #expect(plan.launchExe != nil,
                    "'\(slug)' opts out of the store client but names no exe, so it can never launch")
        }
    }

    @Test("Compatibility is stated honestly", arguments: ProfileDatabaseTests.slugs)
    func honestStatus(_ slug: String) throws {
        let plan = try Game.plan(slug: slug)
        let status = try #require(plan.facts.status, "'\(slug)' has no status — the app would show a blank")
        #expect(["playable", "untested", "broken", "partial"].contains(status),
                "'\(slug)' has status '\(status)', which the app has no vocabulary for")

        // A profile claiming "playable" is claiming somebody ran it. Notes are where that is
        // recorded — which hardware, which caveats — and the app prints them verbatim.
        if status == "playable" {
            let notes = try #require(plan.facts.notes, "'\(slug)' claims playable but records nothing about it")
            #expect(notes.count > 20, "'\(slug)' claims playable with a note too short to be evidence")
        }
    }

    @Test("Compatibility facts a player needs before installing are present",
          arguments: ProfileDatabaseTests.slugs)
    func compatibilityFactsPresent(_ slug: String) throws {
        let plan = try Game.plan(slug: slug)
        #expect(plan.facts.anticheat != nil, "'\(slug)' does not say whether it has anti-cheat")
        #expect(plan.facts.drm != nil, "'\(slug)' does not say what DRM it carries")
        #expect(!plan.facts.compatibility.isEmpty)
    }

    @Test("The legal boundary is declared and never crossed", arguments: ProfileDatabaseTests.slugs)
    func legalBoundary(_ slug: String) throws {
        let text = try String(contentsOf: Self.directory.appendingPathComponent("\(slug).toml"),
                              encoding: .utf8)
        #expect(text.contains("drm_circumvention"),
                "'\(slug)' does not declare its DRM stance — see docs/LEGAL.md")
        #expect(text.contains(#"drm_circumvention = "never""#),
                "'\(slug)' must declare drm_circumvention = \"never\"")

        // Hard project rule: Cellar runs DRM through the layer untouched.
        let forbidden = ["crack", "no-cd", "nocd", "bypass anti-cheat", "keygen", "drm removal"]
        for word in forbidden {
            #expect(!text.lowercased().contains(word), "'\(slug)' mentions '\(word)'")
        }
    }

    @Test("A slug is filesystem-safe and matches what the profile calls itself",
          arguments: ProfileDatabaseTests.slugs)
    func slugsAreWellFormed(_ slug: String) throws {
        #expect(slug == slug.lowercased())
        #expect(slug.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" },
                "'\(slug)' has characters that will not survive being a bottle directory name")

        let fields = ProfileStore.fields(try #require(ProfileStore.find(slug)))
        if let declared = fields["slug"] {
            #expect(declared == slug, "'\(slug).toml' declares slug = \"\(declared)\"")
        }
    }

    @Test("Artwork URLs, where a profile supplies them, are usable",
          arguments: ProfileDatabaseTests.slugs)
    func artworkURLs(_ slug: String) throws {
        let plan = try Game.plan(slug: slug)
        for url in [plan.artPortraitURL, plan.artHeroURL].compactMap({ $0 }) {
            #expect(url.hasPrefix("https://"), "'\(slug)' has a non-HTTPS art URL")
            #expect(URL(string: url) != nil, "'\(slug)' has an art URL that will not parse: \(url)")
        }
        if plan.store != .steam {
            // Only Steam publishes free cover art keyed on an app id; every other store has to
            // bring URLs or fall back to Cellar's generated cover. Stardew Valley is the case that
            // matters: it carries a steam_appid but is a `standalone` profile.
            let summary = Game.summaries().first { $0.slug == slug }
            #expect(summary?.artworkAppID == nil,
                    "'\(slug)' is not a Steam game, so it must not fetch Steam artwork")
        }
    }

    @Test("Bottles are only shared deliberately")
    func sharedBottlesAreIntentional() throws {
        var byBottle: [String: [String]] = [:]
        for slug in Self.slugs {
            let plan = try Game.plan(slug: slug)
            byBottle[plan.bottleName, default: []].append(slug)
        }
        for (bottle, slugs) in byBottle where slugs.count > 1 {
            // Several games in one bottle is a supported choice, but they must at least agree on
            // the runner — a bottle has exactly one Wine.
            let runners = try Set(slugs.map { try Game.plan(slug: $0).runnerID })
            #expect(runners.count == 1,
                    "bottle '\(bottle)' is shared by \(slugs) with different runners: \(runners)")
            let stores = try Set(slugs.map { try Game.plan(slug: $0).store })
            #expect(stores.count == 1,
                    "bottle '\(bottle)' is shared across stores \(stores) — one bottle holds one client")
        }
    }

    @Test("Every profile's env values are plain strings Wine can take",
          arguments: ProfileDatabaseTests.slugs)
    func envValuesAreClean(_ slug: String) throws {
        let plan = try Game.plan(slug: slug)
        for (key, value) in plan.env {
            #expect(!key.isEmpty)
            #expect(!key.contains(" "), "'\(slug)' has an env key with a space: '\(key)'")
            #expect(!value.contains("\""), "'\(slug)' left a quote in \(key)=\(value)")
            #expect(!value.hasPrefix("#"), "'\(slug)' read a comment as the value of \(key)")
        }
    }
}
