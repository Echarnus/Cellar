import Foundation
import Testing
@testable import CellarKit

/// The install progress bar and the headless prefix: what the app is told while a game goes on,
/// and the check that keeps Wine's own "Please wait" box off the screen.
@Suite
struct InstallProgressTests {

    // MARK: - Markers

    @Test("A marker round-trips, with and without a fraction", arguments: InstallPhase.allCases)
    func markerRoundTrips(_ phase: InstallPhase) {
        #expect(InstallMarker.progress(in: InstallMarker.line(InstallProgress(phase))) == InstallProgress(phase))
        let half = InstallProgress(phase, fraction: 0.5)
        #expect(InstallMarker.progress(in: InstallMarker.line(half)) == half)
    }

    @Test("Ordinary output is never mistaken for a marker")
    func proseIsNotAMarker() {
        #expect(InstallMarker.progress(in: "  Downloading Planet Coaster 2 from your Steam library…") == nil)
        #expect(InstallMarker.progress(in: "::cellar-progress::teleporting") == nil)
        #expect(InstallMarker.progress(in: LaunchMarker.line(.preparing)) == nil)
    }

    @Test("A fraction is clamped to the bar")
    func fractionIsClamped() {
        #expect(InstallProgress(.downloading, fraction: 1.3).fraction == 1)
        #expect(InstallProgress(.downloading, fraction: -0.2).fraction == 0)
    }

    @Test("Every phase has a title and a sentence, for every store",
          arguments: InstallPhase.allCases)
    func everyPhaseHasCopy(_ phase: InstallPhase) {
        for store in GameStore.allCases {
            #expect(!phase.title(game: "Fixture", store: store).isEmpty)
            let detail = phase.detail(store: store)
            #expect(detail.hasSuffix("."), "a sentence, not a fragment: \"\(detail)\"")
        }
        #expect(InstallPhase.client.detail(store: .battlenet).contains("click through"),
                "Blizzard's installer window must be announced, or it reads as a hang")
    }

    // MARK: - DepotDownloader

    @Test("DepotDownloader's progress lines give the depot's share", arguments: [
        (" 12.34% game\\data\\file.pak", 0.1234),
        ("100.00% game\\PlanetCoaster2.exe", 1.0),
        ("  0,50% game\\data\\file.pak", 0.005),   // a Mac set to a comma-decimal locale
    ])
    func depotLines(_ line: String, _ expected: Double) throws {
        let fraction = try #require(DepotProgress.fraction(in: line))
        #expect(abs(fraction - expected) < 0.0001)
    }

    @Test("Other DepotDownloader output is not progress", arguments: [
        "Got depot key for 2688950 result: OK",
        "Total downloaded: 2044428412 bytes (2044428412 bytes uncompressed) from 1 depots",
        "Downloading depot 2688951 - 100% of the manifest",
        "150.00% nonsense",
        "",
    ])
    func notDepotProgress(_ line: String) {
        #expect(DepotProgress.fraction(in: line) == nil)
    }

    // MARK: - Prefix freshness

    private func prefix(stamp: String?) throws -> (prefix: URL, inf: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-freshness-\(UUID().uuidString)")
        let prefix = root.appendingPathComponent("prefix")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try Data().write(to: prefix.appendingPathComponent("system.reg"))
        let inf = root.appendingPathComponent("wine.inf")
        try Data().write(to: inf)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_788_619_699)],
                                              ofItemAtPath: inf.path)
        if let stamp {
            try stamp.write(to: prefix.appendingPathComponent(".update-timestamp"), atomically: true, encoding: .utf8)
        }
        return (prefix, inf)
    }

    @Test("A prefix built from this runner's wine.inf is current")
    func matchingStampIsCurrent() throws {
        let (prefix, inf) = try prefix(stamp: "1788619699\n")
        #expect(!PrefixFreshness.needsUpdate(prefix: prefix, wineInf: inf))
    }

    @Test("A runner update makes the prefix stale — the case Wine would show its dialog for")
    func differentStampIsStale() throws {
        let (prefix, inf) = try prefix(stamp: "1700000000")
        #expect(PrefixFreshness.needsUpdate(prefix: prefix, wineInf: inf))
        let (unstamped, inf2) = try self.prefix(stamp: nil)
        #expect(PrefixFreshness.needsUpdate(prefix: unstamped, wineInf: inf2))
    }

    @Test("'disable' turns the check off, as it does in Wine")
    func disabledIsNeverStale() throws {
        let (prefix, inf) = try prefix(stamp: "disable")
        #expect(!PrefixFreshness.needsUpdate(prefix: prefix, wineInf: inf))
    }

    @Test("No prefix yet is not an update — creating one is a different step")
    func missingPrefixIsNotAnUpdate() throws {
        let (prefix, inf) = try prefix(stamp: nil)
        try FileManager.default.removeItem(at: prefix.appendingPathComponent("system.reg"))
        #expect(!PrefixFreshness.needsUpdate(prefix: prefix, wineInf: inf))
    }

    @Test("wineboot runs with the Mac display driver off, and keeps Mono and Gecko quiet")
    func bootIsHeadless() {
        let overrides = WineRunner.headlessBootOverrides.split(separator: ";").map(String.init)
        #expect(overrides.contains("winemac.drv=d"))
        #expect(overrides.contains("mscoree=d"))
        #expect(overrides.contains("mshtml=d"))
    }
}
