import Foundation
import Testing
@testable import CellarKit

/// Steam's first update, followed through its own log so Cellar can draw the bar Steam's window
/// would otherwise draw. The lines below are copied from a real `bootstrap_log.txt`.
@Suite
struct SteamClientUpdateTests {

    // MARK: - Progress lines

    private static let total = 336_229.0
    private static let downloadLines: [(String, Double)] = [
        ("[2026-09-16 16:13:54] Update wordt gedownload (5,646 van 336,229 KB)...", 5_646 / total),
        ("[2026-09-16 16:14:58] Update wordt gedownload (236,054 van 236,054 KB)...", 1),
        ("[2026-09-16 16:13:54] Downloading update (5,646 of 336,229 KB)...", 5_646 / total),
        ("[2026-09-16 16:13:54] Update wird heruntergeladen (5.646 von 336.229 KB)...", 5_646 / total),
        ("[2026-09-16 16:13:54] Téléchargement de la mise à jour (5\u{202F}646 sur 336\u{202F}229 Ko)...", 5_646 / total),
    ]

    @Test("A download line gives the pass's share, whatever language Steam writes it in",
          arguments: downloadLines)
    func downloadLines(_ line: String, _ expected: Double) throws {
        let fraction = try #require(SteamClientUpdate.fraction(in: line))
        #expect(abs(fraction - expected) < 0.000_01)
    }

    private static let otherLines: [String] = [
        "[2026-09-16 16:13:52] Update wordt gedownload ...",
        "[2026-09-16 16:14:24] Download voltooid.",
        "[2026-09-16 16:14:24] Pakket uitpakken ...",
        "[2026-09-16 16:14:37] Committing NTFS transaction (0 non-transactional backup files)",
        "[2026-09-16 16:14:24] Saving metrics to disk (C:\\Program Files (x86)\\Steam\\package\\steam_client_metrics.bin)",
        "[2026-09-16 16:14:24] uninstalled manifest found in C:\\Program Files (x86)\\Steam\\package\\steam_client_win32 (1).",
        "[2026-09-16 16:13:53] Downloaded new manifest: /client/steam_client_win32 version 1769731672, installed version 0, existing pending version 0",
        "[2026-09-16 16:14:37] Windows 10.0.19045.0, 0, 2, 256, 1, 28 ",
        "[2026-09-16 16:13:54] Update wordt gedownload (400 van 300 KB)...",
        "",
    ]

    @Test("Everything else the bootstrapper logs is not progress", arguments: otherLines)
    func notProgress(_ line: String) {
        #expect(SteamClientUpdate.fraction(in: line) == nil)
    }

    // MARK: - Done

    @Test("The client is complete only once the 64-bit pass is installed")
    func completeAfterSecondPass() throws {
        let dir = TestHome.scratch("steam-update")
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("package"), withIntermediateDirectories: true)
        #expect(!SteamClientUpdate.isComplete(inSteamDirectory: dir))

        // The first pass leaves steamclient64.dll and the 32-bit manifest — and a second pass to go.
        try Data().write(to: dir.appendingPathComponent("steamclient64.dll"))
        try Data().write(to: dir.appendingPathComponent("package/steam_client_win32.installed"))
        #expect(!SteamClientUpdate.isComplete(inSteamDirectory: dir))

        try Data().write(to: dir.appendingPathComponent("package/steam_client_win64.installed"))
        #expect(SteamClientUpdate.isComplete(inSteamDirectory: dir))
    }

    // MARK: - Following the log

    @Test("Only whole lines are read, and each only once")
    func readsAppendedLines() throws {
        let dir = TestHome.scratch("steam-log")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("bootstrap_log.txt")
        try "old session\n".write(to: log, atomically: true, encoding: .utf8)
        var offset = SteamClientUpdate.fileSize(log)

        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("one\ntw".utf8))
        #expect(SteamClientUpdate.readLines(from: log, offset: &offset) == ["one"])
        try handle.write(contentsOf: Data("o\n".utf8))
        #expect(SteamClientUpdate.readLines(from: log, offset: &offset) == ["two"])
        #expect(SteamClientUpdate.readLines(from: log, offset: &offset).isEmpty)
    }

    @Test("The update has its own phase, told apart from installing the client")
    func phaseCopy() {
        #expect(InstallPhase.clientUpdate.title(game: "Planet Coaster 2", store: .steam) == "Updating Steam")
        #expect(InstallMarker.progress(in: InstallMarker.line(InstallProgress(.clientUpdate, fraction: 0.25)))
                == InstallProgress(.clientUpdate, fraction: 0.25))
    }
}
