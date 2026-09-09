import Foundation
import Testing
@testable import CellarKit

/// The shipped `fallout-shelter` profile, pinned as a worked example.
///
/// `ProfileDatabaseTests` lints every profile for the things all of them must get right. This suite
/// is the opposite: one real game, checked in detail, because Fallout Shelter is the shape Cellar is
/// least able to fake and most likely to break — **a Steam game that runs with no Steam at all**.
///
/// It carries a `steam_appid` (that is where its files come from) while declaring `store =
/// "standalone"` (that is how it launches). Two things follow, and both have gone wrong before:
/// Cellar must not treat it as a Steam game for artwork or for the client it stands up, and it must
/// still find a copy the *Windows Steam client* installed, because a player may well have one.
///
/// The integration counterpart — actually downloading and running it — is `SteamGameTests`.
@Suite(.serialized)
struct FalloutShelterTests {

    static let slug = "fallout-shelter"

    /// Stage the repo's real profile database, so this reads the file the repo ships rather than a
    /// fixture that could drift away from it.
    static let staged: Bool = {
        TestHome.ensure()
        let fm = FileManager.default
        guard let files = try? Repo.profileFiles() else { return false }
        for url in files {
            let target = TestHome.profilesDirectory.appendingPathComponent(url.lastPathComponent)
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: url, to: target)
        }
        return true
    }()

    static func plan() throws -> GamePlan {
        _ = staged
        return try Game.plan(slug: slug)
    }

    // MARK: - The facts the profile claims

    @Test("The profile ships, and names the Steam app its files come from")
    func profileExists() throws {
        let plan = try Self.plan()
        #expect(plan.name == "Fallout Shelter")
        #expect(plan.appID == 588430, "the appid is what DepotDownloader is handed; a wrong one downloads someone else's game")
        #expect(plan.installMethod == "depot", "no store client installs this — Cellar fetches the depot itself")
    }

    @Test("It is a Steam-sourced game that declares no store, which is the whole point of it")
    func storeFreeButSteamSourced() throws {
        let plan = try Self.plan()
        #expect(plan.store == .standalone)
        #expect(plan.needsLiveSession == false,
                "Steam lists no DRM and no third-party account for 588430; requiring a live client would be inventing one")
        #expect(plan.launchExe == "FalloutShelter.exe")
    }

    @Test("Nothing about it promises a store client will be installed")
    func noClientIsStoodUp() throws {
        let plan = try Self.plan()
        #expect(plan.store.descriptor.installsClientInBottle == false,
                "a standalone game must not stand up Windows Steam in its bottle — that is the cost this profile exists to avoid")
    }

    // MARK: - Where its files are looked for

    @Test("A copy the Windows Steam client installed is still found")
    func findsAClientInstalledCopy() throws {
        let plan = try Self.plan()
        let roots = plan.installRoots.map(\.path)

        // Cellar's own download lands here.
        #expect(roots.first == plan.depotGameDir.path)
        // …and `install_dir` is what lets it also find the copy Steam's own client would leave,
        // nested a directory deeper than the plain search reaches.
        #expect(roots.contains { $0.hasSuffix("Steam/steamapps/common/Fallout Shelter") },
                "install_dir 'Fallout Shelter' must reach steamapps/common, or a client-installed copy is invisible")
        #expect(plan.installDir == "Fallout Shelter")
    }

    @Test("The exe is found wherever it was installed, and only when it is really there")
    func directLaunchExeResolves() throws {
        let plan = try Self.plan()
        let fm = FileManager.default

        // Nothing on disk yet: Cellar must not claim it can launch.
        #expect(plan.directLaunchExe == nil)
        #expect(plan.canLaunchStoreFree == false, "no files, so a store-free launch is not on offer")

        // Put the game where the *Steam client* would have put it — the root that is easy to forget.
        let clientRoot = plan.prefix
            .appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common/Fallout Shelter",
                                    isDirectory: true)
        try fm.createDirectory(at: clientRoot, withIntermediateDirectories: true)
        let exe = clientRoot.appendingPathComponent("FalloutShelter.exe")
        try Data("MZ".utf8).write(to: exe)
        defer { try? fm.removeItem(at: plan.prefix) }

        #expect(plan.directLaunchExe?.path == exe.path)
        #expect(plan.canLaunchStoreFree,
                "a DRM-free game whose files are present must launch with no client at all")
    }

    // MARK: - Telling the game apart from everything else running

    @Test("The process needles identify the game itself, not a store client")
    func processNeedlesAreSpecific() throws {
        let plan = try Self.plan()
        let needles = plan.gameProcessNeedles
        #expect(needles.contains("FalloutShelter.exe"))
        #expect(needles.contains { $0.contains("Fallout Shelter") },
                "the install directory is a needle too, so a launcher that re-execs is still matched")

        // The supervised launch kills what it matches. A needle that also matched Steam would take
        // the player's store client down with the game.
        for needle in needles {
            #expect(!needle.lowercased().contains("steam.exe"))
            #expect(needle.count > 3, "'\(needle)' is short enough to match unrelated processes")
        }
    }

    // MARK: - What the player is told

    @Test("With a runner present but no files, Cellar offers Download and does not promise Play")
    func firstStepIsDownload() throws {
        _ = try Self.plan()
        // Without a runner every game's next step is `.setup`, which would say nothing about this
        // profile. The stub satisfies `RunnerManager` and is never executed.
        TestHome.installStubRunner()
        let summary = try #require(Game.summaries().first { $0.slug == Self.slug })

        #expect(summary.gameInstalled == false)
        #expect(summary.nextStep == .install)
        // "Download", not "Install": nothing else is going to do the installing, so the button says
        // what Cellar is about to do itself.
        #expect(summary.actionTitle == "Download")
        #expect(summary.needsLiveSession == false)

        // The step that must *not* appear. A standalone game stands up no client, so demanding one
        // would invent a 1.4 GB detour on the way to a game that does not need it.
        #expect(summary.nextStep != .setup)
        #expect(summary.nextStep != .signIn)
    }

    @Test("It carries a Steam appid but must never be dressed as a Steam game")
    func doesNotBorrowSteamArtwork() throws {
        _ = try Self.plan()
        let summary = try #require(Game.summaries().first { $0.slug == Self.slug })

        // Same trap Stardew Valley documents: `steam_appid` says where the *files* come from, and
        // says nothing about which store the player is dealing with.
        #expect(summary.store == .standalone)
        #expect(summary.artworkAppID == nil,
                "a standalone game must not pull Steam's cover art — the store marks would then lie about it")
    }

    @Test("Its honesty is intact: untested says untested, and the notes are the evidence")
    func statusIsHonest() throws {
        let plan = try Self.plan()
        let status = try #require(plan.facts.status)
        let notes = try #require(plan.facts.notes)

        // This profile was written from Steam's app record, not from a run on this Mac. If someone
        // promotes it to "playable" they must also say what they ran it on — that is the lint's job
        // — but the pairing is asserted here too, because this is the profile most likely to be
        // promoted by whoever finally runs the integration tier.
        if status == "untested" {
            #expect(notes.lowercased().contains("not yet launched"),
                    "an untested profile must say plainly that nobody has run it")
        } else {
            #expect(notes.count > 20)
        }
        #expect(plan.facts.anticheat == "none")
        #expect(try #require(plan.facts.drm).lowercased().contains("none"),
                "Steam publishes no DRM notice for 588430; claiming DRM here would be as wrong as hiding it")
    }
}
