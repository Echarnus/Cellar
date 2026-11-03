import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Tier A: a resumed, multi-depot download read through the real process plumbing (#309).
///
/// A stand-in DepotDownloader — a shell script at the path Cellar runs the tool from — prints what
/// the real one prints for a game with a DLC depot that stopped partway, and records the arguments
/// it was given. The manifests it would have saved are real files in the game folder. Everything
/// between the tool and the bar is the shipping code: `DepotTool.fetch`, its line splitter, the
/// manifest reader and the tracker.
@Suite(.serialized)
struct DownloadProgressIntegrationTests {

    static func manifest(totalSize: UInt64) -> Data {
        func u32(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        var size: [UInt8] = []
        var v = totalSize
        repeat { var b = UInt8(v & 0x7F); v >>= 7; if v != 0 { b |= 0x80 }; size.append(b) } while v != 0
        let metadata: [UInt8] = [0x28] + size
        var bytes: [UInt8] = u32(0x71F6_17D0)
        bytes += u32(0)
        bytes += u32(0x1F48_12BE)
        bytes += u32(UInt32(metadata.count))
        bytes += metadata
        bytes += u32(0x32C4_15AB)
        return Data(bytes)
    }

    @Test("A resumed two-depot download is one bar: checking, then downloading, never backwards")
    func resumedDownload() throws {
        IT.ensure()
        // Tier D copies the real DepotDownloader into the sandbox; never stand in front of it.
        guard !IT.steamTierEnabled, !DepotTool.isInstalled else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: DepotTool.root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: DepotTool.binary) }

        let game = IT.scratch("depot-resume")
        let saved = game.appendingPathComponent(".DepotDownloader", isDirectory: true)
        try fm.createDirectory(at: saved, withIntermediateDirectories: true)
        try Self.manifest(totalSize: 9_000).write(to: saved.appendingPathComponent("100_11.manifest"))
        try Self.manifest(totalSize: 1_000).write(to: saved.appendingPathComponent("200_22.manifest"))
        let argsFile = game.appendingPathComponent("args.txt")

        // The real tool draws its per-file lines with \r as well as \n; so does this one.
        let script = """
        #!/bin/sh
        echo "$@" > '\(argsFile.path)'
        echo "Processing depot 100"
        echo "Already have manifest 11 for depot 100."
        echo "Manifest 11 (11/03/2026 19:00:00)"
        echo "Processing depot 200"
        echo "Already have manifest 22 for depot 200."
        echo "Manifest 22 (11/03/2026 19:00:00)"
        echo "Downloading depot 100"
        printf ' 50.00%% /g/a.bdt\\r100.00%% /g/b.bdt\\n'
        echo "Depot 100 - Downloaded 0 bytes (0 bytes uncompressed)"
        echo "Downloading depot 200"
        echo "Validating /g/dlc/c.bdt"
        echo " 40.00% /g/dlc/c.bdt"
        echo "Pre-allocating /g/dlc/d.bdt"
        echo " 80.00% /g/dlc/d.bdt"
        echo "100.00% /g/dlc/e.bdt"
        echo "Depot 200 - Downloaded 600 bytes (600 bytes uncompressed)"
        echo "Total downloaded: 600 bytes (600 bytes uncompressed) from 2 depots"
        """
        try script.write(to: DepotTool.binary, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: DepotTool.binary.path)

        var bar = DepotDownloadProgress()
        var reports: [InstallProgress] = []
        try DepotTool.fetch(appID: 374320, into: game, credentials: .anonymous) { line in
            if let now = bar.read(line, size: { DepotManifests.totalSize(in: game, depot: $0, manifest: $1) }) {
                reports.append(now)
            }
        }

        let fractions = reports.compactMap(\.fraction)
        #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 <= $1 }, "never backwards: \(fractions)")
        #expect(fractions.last == 1)
        // The game depot is 90% of the bytes, so once it is done the bar is at 90%, not 100%.
        #expect(reports.contains { abs(($0.fraction ?? 0) - 0.9) < 0.0001 })
        #expect(reports.contains { $0.phase == .checkingDownload }, "a resume says it is checking")
        #expect(reports.last?.phase == .downloading)
        #expect(bar.resumed)

        let args = try String(contentsOf: argsFile, encoding: .utf8)
        #expect(args.contains("-max-downloads \(DepotTool.concurrentChunks)"), "args: \(args)")
        #expect(args.contains("-dir \(game.path)"))
    }
}
