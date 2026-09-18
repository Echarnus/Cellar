import Foundation
import Testing
@testable import CellarKit

/// Knowing whether a game Cellar downloaded is on Steam's current build. Both halves are Steam's
/// own records — DepotDownloader's `depot.config` and its `-manifest-only` output — so these tests
/// use the real bytes and the real lines, captured from Planet Coaster 2 on 2026-09-18.
struct GameUpdateTests {

    /// `.DepotDownloader/depot.config` exactly as DepotDownloader 3.4.0 wrote it.
    static let depotConfig = Data([
        0x01, 0x31, 0x00, 0xce, 0xff, 0x0a, 0x0e, 0x08, 0xfd, 0xfc, 0x0d, 0x10, 0xb6, 0xed, 0xa2, 0xbf,
        0xea, 0xc1, 0xb5, 0xec, 0x4f, 0x0a, 0x0e, 0x08, 0xfe, 0xfc, 0x0d, 0x10, 0x83, 0xa6, 0xc0, 0xd8,
        0xd0, 0xd5, 0x9f, 0xb2, 0x19, 0x0a, 0x0f, 0x08, 0xb7, 0x8f, 0xa4, 0x01, 0x10, 0x8d, 0xf5, 0x8c,
        0x9c, 0x9b, 0xad, 0xdd, 0x9c, 0x4d,
    ])

    static let installed: [UInt32: UInt64] = [
        228_989: 5_753_583_882_400_741_046,
        228_990: 1_829_726_630_299_308_803,
        2_688_951: 5_564_607_911_436_696_205,
    ]

    @Test("depot.config decodes to the manifest installed for each depot")
    func decodesDepotConfig() {
        #expect(DepotManifests.decodeDepotConfig(Self.depotConfig) == Self.installed)
    }

    @Test("A depot.config that doesn't parse is nil, never a guess")
    func garbageIsNil() {
        #expect(DepotManifests.decodeDepotConfig(Data([0xde, 0xad, 0xbe, 0xef])) == nil)
        // A truncated map entry: the length says 14 bytes, two follow.
        #expect(DepotManifests.decodeManifestMap(Data([0x0a, 0x0e, 0x08, 0x01])) == nil)
    }

    @Test("No depot.config means Cellar didn't download this copy")
    func missingConfig() {
        #expect(DepotManifests.installed(in: TestHome.scratch("no-depot")) == nil)
    }

    @Test("A depot.config on disk is read from the game's folder")
    func readsFromDisk() throws {
        let game = TestHome.scratch("game")
        let dir = game.appendingPathComponent(".DepotDownloader")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Self.depotConfig.write(to: dir.appendingPathComponent("depot.config"))
        #expect(DepotManifests.installed(in: game) == Self.installed)
    }

    /// The `-manifest-only` run for the same app, as the tool printed it.
    static let listingOutput = """
    Connecting to Steam3... Done!
    Logging 'someone' into Steam3...
     Done!
    Using Steam3 suggested CellID: 86
    Got 379 licenses for account!
    Got AppInfo for 2688950
    Using app branch: 'public'.
    Got AppInfo for 228980
    Got depot key for 228989 result: OK
    Got depot key for 228990 result: OK
    Got depot key for 2688951 result: OK
    Processing depot 228989
    Downloading depot 228989 manifest
    Got manifest request code for depot 228989 from app 228980, manifest 5753583882400741046, result: 13433167993843185461
    Manifest 5753583882400741046 (06/30/2026 23:39:35)
    Processing depot 228990
    Downloading depot 228990 manifest
    Got manifest request code for depot 228990 from app 228980, manifest 1829726630299308803, result: 5787230874006238617
    Manifest 1829726630299308803 (02/18/2013 21:47:57)
    Processing depot 2688951
    Downloading depot 2688951 manifest
    Got manifest request code for depot 2688951 from app 2688950, manifest 5564607911436696205, result: 3158914721163363485
    Manifest 5564607911436696205 (08/20/2026 16:55:54)
    Total downloaded: 0 bytes (0 bytes uncompressed) from 3 depots
    """.components(separatedBy: "\n")

    @Test("A manifest-only run yields the manifest Steam serves for every depot")
    func readsListing() {
        var listing = DepotManifests.Listing()
        for line in Self.listingOutput { listing.read(line) }
        #expect(listing.isComplete)
        #expect(listing.failure == nil)
        #expect(listing.manifests == Self.installed)
    }

    @Test("The listing knows it is done at the last depot, so the run can stop there")
    func completesEarly() {
        var listing = DepotManifests.Listing()
        let lastRequest = Self.listingOutput.firstIndex { $0.contains("for depot 2688951 from app") }!
        for line in Self.listingOutput[..<lastRequest] {
            listing.read(line)
            #expect(!listing.isComplete, "complete too early, at: \(line)")
        }
        listing.read(Self.listingOutput[lastRequest])
        #expect(listing.isComplete)
    }

    @Test("Before any depot key arrives, nothing is complete — an empty answer is not an answer")
    func emptyIsNotComplete() {
        var listing = DepotManifests.Listing()
        for line in Self.listingOutput.prefix(5) { listing.read(line) }
        #expect(!listing.isComplete)
    }

    @Test("Steam refusing is a failure with its reason, not a listing")
    func refusals() {
        var expired = DepotManifests.Listing()
        expired.read("Access token was rejected for someone")
        #expect(expired.isComplete)
        #expect(expired.failure == "your Steam sign-in has expired")

        var notOwned = DepotManifests.Listing()
        notOwned.read("App 2688950 (Planet Coaster 2) is not available from this account.")
        #expect(notOwned.failure != nil)
    }

    @Test("Same manifests on both sides is up to date; any depot behind is an update")
    func verdict() {
        let now = Date()
        #expect(UpdateRecord(checked: now, latest: Self.installed).state(against: Self.installed)
            == .upToDate(checked: now))

        var patched = Self.installed
        patched[2_688_951] = 1
        #expect(UpdateRecord(checked: now, latest: patched).state(against: Self.installed)
            == .available(checked: now))

        // A depot Steam now serves that was never downloaded is also something to fetch.
        var grown = Self.installed
        grown[3_000_000] = 42
        #expect(UpdateRecord(checked: now, latest: grown).state(against: Self.installed)
            == .available(checked: now))
    }

    @Test("A finished update reads as up to date without asking Steam again")
    func verdictFollowsTheDisk() {
        // The record keeps manifest ids, not a verdict: once depot.config catches up, so does the state.
        var patched = Self.installed
        patched[2_688_951] = 1
        let record = UpdateRecord(checked: Date(), latest: patched)
        #expect(record.state(against: patched) == .upToDate(checked: record.checked))
    }

    @Test("The last answer survives a round trip to disk")
    func recordRoundTrip() {
        let slug = "update-record-\(UUID().uuidString)"
        let record = UpdateRecord(checked: Date(timeIntervalSince1970: 1_789_700_000), latest: Self.installed)
        record.save(slug: slug)
        #expect(UpdateRecord.load(slug: slug) == record)
        #expect(UpdateRecord.load(slug: "never-checked-\(UUID().uuidString)") == nil)
    }

    @Test("A failure says whether the files were touched")
    func failureWording() {
        #expect(GameUpdates.UpdateFailure.notStarted("offline").errorDescription == "offline")
        #expect(GameUpdates.UpdateFailure.alreadyDownloading.errorDescription?.contains("already") == true)
    }

    @Test("No download is running into a folder nobody is downloading into")
    func noStrayDownload() {
        #expect(!DepotTool.isDownloading(into: TestHome.scratch("idle-game")))
    }

    @Test("Only a recent confirmed answer is fresh")
    func freshness() {
        let now = Date()
        #expect(GameUpdates.isFresh(.upToDate(checked: now.addingTimeInterval(-60)), within: 900, now: now))
        #expect(!GameUpdates.isFresh(.upToDate(checked: now.addingTimeInterval(-3600)), within: 900, now: now))
        #expect(!GameUpdates.isFresh(.unknown("offline"), within: 900, now: now))
        #expect(!GameUpdates.isFresh(nil, within: 900, now: now))
    }

    @Test("The new phases have words")
    func phaseWording() {
        #expect(InstallPhase.updating.title(game: "Planet Coaster 2", store: .steam) == "Updating Planet Coaster 2")
        #expect(InstallPhase.updateCheck.detail(store: .steam).contains("Steam"))
    }
}
