import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// One bar for a whole Steam download (#309).
///
/// DepotDownloader's percentage is per depot. Dark Souls III has its game depot and DLC depots, so
/// reading the number straight filled the bar three times, and a resumed download raced through
/// the files already on disk under the word "Downloading". These feed the tracker the lines the
/// tool really prints (DepotDownloader 3.4.0, `ContentDownloader.cs`) and hold the bar to one run,
/// weighted by size, that never goes backwards.
@Suite
struct DepotDownloadProgressTests {

    static let gigabyte: UInt64 = 1 << 30

    /// What DepotDownloader prints for a depot from `Processing` to its manifest line.
    static func processing(_ depot: UInt32, manifest: UInt64) -> [String] {
        ["Processing depot \(depot)", "Downloading depot \(depot) manifest",
         "Manifest \(manifest) (11/03/2026 19:00:00)"]
    }

    /// Feed `lines`, returning every progress the bar was told.
    static func run(_ lines: [String], sizes: [UInt32: UInt64],
                    tracker: inout DepotDownloadProgress) -> [InstallProgress] {
        lines.compactMap { line in tracker.read(line) { depot, _ in sizes[depot] } }
    }

    static let ds3: [UInt32: UInt64] = [374321: 22 * gigabyte, 374322: 2 * gigabyte, 374323: 2 * gigabyte]

    /// A fresh download of three depots, each counting its own 0 → 100%.
    static var freshDownload: [String] {
        var lines = processing(374321, manifest: 11) + processing(374322, manifest: 22)
            + processing(374323, manifest: 33)
        for depot: UInt32 in [374321, 374322, 374323] {
            lines.append("Downloading depot \(depot)")
            lines.append("Pre-allocating /games/ds3/Game/file\(depot).bdt")
            for percent in stride(from: 10, through: 100, by: 10) {
                lines.append(" \(percent).00% /games/ds3/Game/file\(depot)-\(percent).bdt")
            }
            lines.append("Depot \(depot) - Downloaded 1234 bytes (5678 bytes uncompressed)")
        }
        lines.append("Total downloaded: 1234 bytes (5678 bytes uncompressed) from 3 depots")
        return lines
    }

    @Test("The bar fills once for the whole game, not once per depot")
    func oneBarAcrossDepots() throws {
        var tracker = DepotDownloadProgress()
        let reports = Self.run(Self.freshDownload, sizes: Self.ds3, tracker: &tracker)
        let fractions = reports.compactMap(\.fraction)
        #expect(!fractions.isEmpty)
        // The regression itself: the second depot's " 10.00%" used to pull the bar back to 10%.
        #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 <= $1 }, "the bar never goes backwards")
        // The last depot's 100% and its "Downloaded" line are the only full bars.
        #expect(fractions.dropLast(2).allSatisfy { $0 < 1 }, "it reaches 100% once, at the end")
        #expect(fractions.last == 1)
        #expect(reports.allSatisfy { $0.phase == .downloading }, "a fresh download checks nothing")
        #expect(!tracker.resumed)
    }

    @Test("Each depot counts for its size: the game depot is most of the bar")
    func weightedBySize() {
        var tracker = DepotDownloadProgress()
        let lines = Self.processing(374321, manifest: 11) + Self.processing(374322, manifest: 22)
            + Self.processing(374323, manifest: 33)
            + ["Downloading depot 374321", "100.00% /games/ds3/Game/data1.bdt"]
        _ = Self.run(lines, sizes: Self.ds3, tracker: &tracker)
        // 22 of 26 GB.
        #expect(abs(tracker.fraction - 22.0 / 26.0) < 0.0001)
    }

    @Test("A depot whose size can't be read gives every depot an equal share — still one bar")
    func unknownSizes() {
        var tracker = DepotDownloadProgress()
        let reports = Self.run(Self.freshDownload, sizes: [374321: 22 * Self.gigabyte], tracker: &tracker)
        let fractions = reports.compactMap(\.fraction)
        #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(fractions.last == 1)
        let afterFirst = Self.processing(374321, manifest: 11) + Self.processing(374322, manifest: 22)
            + Self.processing(374323, manifest: 33) + ["Downloading depot 374321", "100.00% /x"]
        var equal = DepotDownloadProgress()
        _ = Self.run(afterFirst, sizes: [:], tracker: &equal)
        #expect(abs(equal.fraction - 1.0 / 3.0) < 0.0001)
    }

    @Test("A resumed download says it is checking, then downloading, and the checked files count")
    func resumeIsChecking() throws {
        var tracker = DepotDownloadProgress()
        // The first depot finished last time: its manifest is remembered, so it is skipped through.
        var lines = ["Processing depot 374321", "Already have manifest 11 for depot 374321.",
                     "Manifest 11 (11/03/2026 19:00:00)"]
            + Self.processing(374322, manifest: 22)
        lines += ["Downloading depot 374321", "100.00% /games/ds3/Game/data1.bdt",
                  "Depot 374321 - Downloaded 0 bytes (0 bytes uncompressed)"]
        // The second stopped partway: every file on disk is checked before anything is fetched.
        lines += ["Downloading depot 374322",
                  "Validating /games/ds3/DLC/a.bdt", "Validating /games/ds3/DLC/b.bdt",
                  " 40.00% /games/ds3/DLC/a.bdt"]
        let checking = Self.run(lines, sizes: Self.ds3, tracker: &tracker)
        #expect(tracker.resumed)
        #expect(checking.last?.phase == .checkingDownload, "a file found whole is part of the check")
        #expect(checking.contains { $0.phase == .checkingDownload })
        // b.bdt was half there: its missing chunks are fetched, and that is downloading.
        let fetching = Self.run([" 70.00% /games/ds3/DLC/c.bdt", "100.00% /games/ds3/DLC/b.bdt",
                                 "Depot 374322 - Downloaded 1 bytes (1 bytes uncompressed)"],
                                sizes: Self.ds3, tracker: &tracker)
        #expect(fetching.first?.phase == .downloading)
        #expect(tracker.fraction == 1)
        let all = (checking + fetching).compactMap(\.fraction)
        #expect(zip(all, all.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test("An update keeps its own phase")
    func updatePhase() {
        var tracker = DepotDownloadProgress(phase: .updating)
        let reports = Self.run(Self.freshDownload, sizes: Self.ds3, tracker: &tracker)
        #expect(reports.allSatisfy { $0.phase == .updating })
    }

    @Test("Output with no depot lines still draws the one percentage there is")
    func bareProgress() {
        var tracker = DepotDownloadProgress()
        #expect(tracker.read(" 12.50% file.pak") { _, _ in nil } == InstallProgress(.downloading, fraction: 0.125))
        #expect(tracker.read("Got depot key for 1 result: OK") { _, _ in nil } == nil)
        #expect(tracker.read("Depot 1 is not available from this account.") { _, _ in nil } == nil)
    }

    // MARK: - The manifest's size

    /// SteamKit's manifest layout: payload section, metadata section, signature, end marker.
    static func manifestFile(totalSize: UInt64, payload: [UInt8] = [0x0A, 0x02, 0x08, 0x01]) -> Data {
        func u32(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        func varint(_ v: UInt64) -> [UInt8] {
            var v = v, out: [UInt8] = []
            repeat { var b = UInt8(v & 0x7F); v >>= 7; if v != 0 { b |= 0x80 }; out.append(b) } while v != 0
            return out
        }
        // depot_id = 374321, gid_manifest = 11, cb_disk_original = totalSize, cb_disk_compressed = 7
        var metadata: [UInt8] = [0x08]
        metadata += varint(374321)
        metadata += [0x10]
        metadata += varint(11)
        metadata += [0x28]
        metadata += varint(totalSize)
        metadata += [0x30]
        metadata += varint(7)
        var bytes: [UInt8] = u32(0x71F6_17D0)
        bytes += u32(UInt32(payload.count))
        bytes += payload
        bytes += u32(0x1F48_12BE)
        bytes += u32(UInt32(metadata.count))
        bytes += metadata
        bytes += u32(0x1B81_B817)
        bytes += u32(0)
        bytes += u32(0x32C4_15AB)
        return Data(bytes)
    }

    @Test("A saved manifest gives its depot's size")
    func manifestSize() throws {
        let size = 23_622_320_128 as UInt64   // Dark Souls III's game depot, roughly
        #expect(DepotManifests.decodeTotalSize(Array(Self.manifestFile(totalSize: size))) == size)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-manifest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent(".DepotDownloader", isDirectory: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try Self.manifestFile(totalSize: size).write(to: config.appendingPathComponent("374321_11.manifest"))
        #expect(DepotManifests.totalSize(in: dir, depot: 374321, manifest: 11) == size)
        #expect(DepotManifests.totalSize(in: dir, depot: 374321, manifest: 12) == nil, "another build is not this one")
    }

    @Test("A manifest that doesn't parse has no size, never a guess", arguments: [
        Data(),
        Data([1, 2, 3]),
        Data("not a manifest at all".utf8),
        // A payload that claims more bytes than there are.
        Data([0xD0, 0x17, 0xF6, 0x71, 0xFF, 0x00, 0x00, 0x00, 0x01]),
    ])
    func manifestGarbage(_ data: Data) {
        #expect(DepotManifests.decodeTotalSize(Array(data)) == nil)
    }

    // MARK: - Speed and copy

    @Test("A game download keeps more chunks in flight than DepotDownloader's default of 8")
    func concurrency() {
        #expect(DepotTool.concurrentChunks > 8)
        #expect(DepotTool.concurrentChunks <= 25, "no more than DepotDownloader uses against a local cache")
    }

    @Test("Checking reads as checking, everywhere the activity is said")
    func checkingCopy() {
        let activity = GameActivity.working(InstallProgress(.checkingDownload, fraction: 0.4))
        #expect(activity.statusText.hasPrefix("Checking"))
        #expect(activity.statusText.contains("40"))
        #expect(activity.isDownloading, "the sidebar and chip keep the download mark")
        #expect(InstallPhase.checkingDownload.title(game: "DARK SOULS III", store: .steam)
                == "Checking what's already downloaded")
        #expect(InstallPhase.checkingDownload.detail(store: .steam).contains("Nothing downloads twice"))
    }
}
