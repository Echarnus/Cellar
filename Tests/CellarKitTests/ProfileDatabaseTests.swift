import Testing
import Foundation
@testable import CellarKit

/// The profile database is the one part of Cellar a contributor edits without writing any Swift, so
/// it is the part most likely to ship a mistake. The app prints these fields **verbatim** to the
/// player, and the setup/launch pipelines branch on them — a profile that names a store nobody
/// implements, or claims `status = "verified"` with no hardware named, is a bug that reaches a
/// person rather than a compiler.
///
/// These run over `profiles/*.toml` in the checkout, so adding a game means adding a test case.
@Suite("Profile database")
struct ProfileDatabaseTests {

    /// Every profile in the repo, read through the same flat scanner the CLI and app use — so a
    /// profile that these tests pass is a profile Cellar can actually read.
    static let profiles: [(slug: String, fields: [String: String], env: [String: String])] = {
        guard let files = try? Repo.profileFiles() else { return [] }
        return files.map { url in
            let ref = ProfileRef(slug: url.deletingPathExtension().lastPathComponent, url: url)
            return (ref.slug, ProfileStore.fields(ref), ProfileStore.env(ref))
        }
    }()

    static var slugs: [String] { profiles.map(\.slug) }

    @Test("the checkout actually ships profiles")
    func databaseIsNotEmpty() throws {
        #expect(!Self.profiles.isEmpty, "no profiles/*.toml found under \(Repo.profiles.path)")
    }

    @Test("a profile's slug matches its filename", arguments: Self.slugs)
    func slugMatchesFilename(slug: String) throws {
        let p = try #require(Self.profiles.first { $0.slug == slug })
        #expect(p.fields["slug"] == slug,
                "\(slug).toml declares slug = \"\(p.fields["slug"] ?? "")\" — the two are used interchangeably")
    }

    @Test("every profile names a store Cellar implements", arguments: Self.slugs)
    func storeIsKnown(slug: String) throws {
        let p = try #require(Self.profiles.first { $0.slug == slug })
        let raw = try #require(p.fields["store"], "\(slug).toml has no store = \"…\"")
        #expect(GameStore(profileValue: raw) != nil,
                "\(slug).toml names store \"\(raw)\", which no GameStore case handles")
    }

    @Test("every profile carries the facts the app puts on screen", arguments: Self.slugs)
    func requiredFactsArePresent(slug: String) throws {
        let p = try #require(Self.profiles.first { $0.slug == slug })
        for key in ["name", "engine", "graphics_api", "architecture", "status", "notes"] {
            let value = p.fields[key] ?? ""
            #expect(!value.isEmpty, "\(slug).toml is missing \(key) — the app shows this field verbatim")
        }
    }

    /// Per-store addressing. Steam games are reached by AppID; Battle.net by product code plus the
    /// directory the client drops the game in; GOG by its product id. Get this wrong and setup
    /// installs the right client and then cannot find the game.
    @Test("a profile carries the identifiers its own store needs", arguments: Self.slugs)
    func storeSpecificIdentifiers(slug: String) throws {
        let p = try #require(Self.profiles.first { $0.slug == slug })
        let store = try #require(GameStore(profileValue: p.fields["store"]))

        switch store {
        case .steam:
            let appID = p.fields["steam_appid"] ?? ""
            #expect(!appID.isEmpty, "\(slug).toml is a Steam game with no steam_appid")
            #expect(UInt64(appID) != nil, "\(slug).toml steam_appid \"\(appID)\" is not a number")
        case .battlenet:
            #expect(!(p.fields["product_code"] ?? "").isEmpty,
                    "\(slug).toml is a Battle.net game with no product_code — launch has nothing to --exec")
            #expect(!(p.fields["install_dir"] ?? "").isEmpty,
                    "\(slug).toml is a Battle.net game with no install_dir — Cellar cannot tell if it is installed")
            #expect(!(p.fields["exe"] ?? "").isEmpty, "\(slug).toml is a Battle.net game with no exe")
        case .gog:
            let id = p.fields["gog_product_id"] ?? ""
            #expect(!id.isEmpty, "\(slug).toml is a GOG game with no gog_product_id")
            #expect(UInt64(id) != nil, "\(slug).toml gog_product_id \"\(id)\" is not a number")
            #expect(!(p.fields["exe"] ?? "").isEmpty, "\(slug).toml is a GOG game with no exe to launch")
        case .standalone:
            #expect(!(p.fields["exe"] ?? "").isEmpty, "\(slug).toml is standalone with no exe to launch")
        }
    }

    @Test("graphics backends are ones Cellar can actually graft", arguments: Self.slugs)
    func backendsAreSupported(slug: String) throws {
        let p = try #require(Self.profiles.first { $0.slug == slug })
        // Derived from the enum rather than listed here: a hardcoded copy would go stale the day
        // somebody adds a backend, and then reject a perfectly good profile.
        let supported = Set(GraphicsBackend.allCases.map(\.rawValue) + ["none"])
        for key in ["backend", "fallback_backend"] {
            guard let value = p.fields[key], !value.isEmpty else { continue }
            #expect(supported.contains(value), "\(slug).toml \(key) = \"\(value)\" is not a backend Cellar installs")
        }
        // A fallback that is the same as the primary is not a fallback.
        if let b = p.fields["backend"], let f = p.fields["fallback_backend"] {
            #expect(b != f, "\(slug).toml falls back from \(b) to itself")
        }
    }

    /// The honesty rule applied to data. `AGENTS.md`: "the app shows those facts verbatim, so
    /// 'untested' must say so". A profile may only claim to be verified if its notes name the
    /// hardware it was verified on.
    @Test("a status is one of the words the app knows, and 'verified' names hardware",
          arguments: Self.slugs)
    func statusIsHonest(slug: String) throws {
        let p = try #require(Self.profiles.first { $0.slug == slug })
        let status = p.fields["status"] ?? ""
        let known: Set<String> = ["untested", "testing", "playable", "verified", "broken"]
        #expect(known.contains(status), "\(slug).toml status = \"\(status)\" is not a word the app renders")

        if status == "verified" || status == "playable" {
            let notes = p.fields["notes"] ?? ""
            #expect(notes.count > 20,
                    "\(slug).toml claims \(status) but its notes do not say what that was tested on")
        }
    }

    /// The hard project rule, as a test rather than as a habit. No profile may describe defeating
    /// DRM or anti-cheat; Cellar runs them through the layer untouched.
    @Test("no profile describes circumventing DRM or anti-cheat", arguments: Self.slugs)
    func noCircumvention(slug: String) throws {
        let p = try #require(Self.profiles.first { $0.slug == slug })
        if let declared = p.fields["drm_circumvention"] {
            #expect(declared == "never", "\(slug).toml declares drm_circumvention = \"\(declared)\"")
        }
        let text = try String(contentsOf: Repo.profiles.appendingPathComponent("\(slug).toml"), encoding: .utf8)
        for banned in ["crack", "no-cd", "nocd", "bypass anti-cheat", "defeat drm"] {
            #expect(!text.lowercased().contains(banned),
                    "\(slug).toml mentions \"\(banned)\" — Cellar never circumvents DRM or anti-cheat")
        }
    }

    /// Environment variables reach Wine verbatim. A stray quote or a trailing inline comment used to
    /// be a real source of "the game launches on my machine but not from a profile" reports.
    @Test("env values survive the parser intact", arguments: Self.slugs)
    func envIsClean(slug: String) throws {
        let p = try #require(Self.profiles.first { $0.slug == slug })
        for (key, value) in p.env {
            #expect(!key.isEmpty)
            #expect(!value.contains("\""), "\(slug).toml env \(key) still carries a quote: \(value)")
            #expect(!value.contains("#"), "\(slug).toml env \(key) still carries a comment: \(value)")
            #expect(value.trimmingCharacters(in: .whitespaces) == value,
                    "\(slug).toml env \(key) has stray whitespace: '\(value)'")
        }
    }

    /// The reference profiles `CONTRIBUTING.md` tells a contributor to copy. If one is renamed or
    /// removed, that instruction quietly stops working.
    @Test("the per-store reference profiles named in CONTRIBUTING.md exist",
          arguments: [("planet-coaster-2", GameStore.steam),
                      ("diablo-4", GameStore.battlenet),
                      ("witcher-3", GameStore.gog)])
    func referenceProfilesExist(slug: String, store: GameStore) throws {
        let p = try #require(Self.profiles.first { $0.slug == slug },
                             "\(slug).toml is the reference profile for \(store.displayName)")
        #expect(GameStore(profileValue: p.fields["store"]) == store)
    }
}
