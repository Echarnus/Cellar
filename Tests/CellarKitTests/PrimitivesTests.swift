import Testing
import Foundation
@testable import CellarKit

/// The small, exact pieces underneath the pipelines. None of them need a machine with Wine on it,
/// which is what makes them worth having: they run anywhere, in a second.
@Suite("Primitives")
struct PrimitivesTests {

    /// The Steam shortcut app id is derived from a CRC32, so a wrong table means every non-Steam
    /// shortcut Cellar writes points at the wrong entry. Vectors are the published IEEE ones.
    @Suite("CRC32")
    struct CRC32Tests {
        @Test("known IEEE vectors",
              arguments: [("", UInt32(0x0000_0000)),
                          ("a", 0xE8B7_BE43),
                          ("abc", 0x3524_41C2),
                          ("message digest", 0x2015_9D7F),
                          ("123456789", 0xCBF4_3926)])
        func knownVectors(input: String, expected: UInt32) {
            #expect(CRC32.checksum(input) == expected)
        }

        @Test("the string and byte forms agree")
        func stringMatchesBytes() {
            let s = "cellar/planet-coaster-2"
            #expect(CRC32.checksum(s) == CRC32.checksum(Array(s.utf8)))
        }
    }

    /// A CDN answers an outage with a valid HTML error page. Handing that to Wine fails in a way
    /// nobody can read, so every downloaded installer is checked for the `MZ` magic first.
    @Suite("Windows installer sniffing")
    struct InstallerTests {
        private func tempFile(_ bytes: [UInt8]) throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("cellar-test-\(UUID().uuidString)")
            try Data(bytes).write(to: url)
            return url
        }

        @Test("a real PE is accepted")
        func acceptsPE() throws {
            let url = try tempFile([0x4D, 0x5A, 0x90, 0x00])   // "MZ" + padding
            defer { try? FileManager.default.removeItem(at: url) }
            #expect(WindowsInstaller.isPortableExecutable(url))
        }

        @Test("an HTML error page from a CDN is rejected")
        func rejectsHTML() throws {
            let url = try tempFile(Array("<!DOCTYPE html><title>503</title>".utf8))
            defer { try? FileManager.default.removeItem(at: url) }
            #expect(WindowsInstaller.isPortableExecutable(url) == false)
        }

        @Test("an empty file is rejected rather than crashing")
        func rejectsEmpty() throws {
            let url = try tempFile([])
            defer { try? FileManager.default.removeItem(at: url) }
            #expect(WindowsInstaller.isPortableExecutable(url) == false)
        }

        @Test("a file that is not there is rejected rather than crashing")
        func rejectsMissing() {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("cellar-test-does-not-exist-\(UUID().uuidString)")
            #expect(WindowsInstaller.isPortableExecutable(url) == false)
        }
    }

    /// Paths are pure derivations, and every one of them is somewhere Cellar will later write. A
    /// path that escaped Application Support would put game-sized downloads somewhere surprising.
    @Suite("Paths")
    struct PathTests {
        @Test("every derived directory stays under Application Support")
        func staysUnderAppSupport() {
            let base = Paths.appSupport.standardizedFileURL.path
            for url in [Paths.runners, Paths.prefixes, Paths.cache, Paths.shared,
                        Paths.sharedSteam, Paths.logs, Paths.userProfiles, Paths.d3dmetalCache] {
                #expect(url.standardizedFileURL.path.hasPrefix(base),
                        "\(url.path) is outside \(base)")
            }
        }

        /// One Windows Steam install behind every bottle is the whole point of `shared/steam`; if it
        /// stopped living under `shared`, each bottle would go back to its own 1.4 GB client.
        @Test("the shared Steam install lives under shared/")
        func sharedSteamIsShared() {
            #expect(Paths.sharedSteam.standardizedFileURL.path
                .hasPrefix(Paths.shared.standardizedFileURL.path))
            #expect(Paths.sharedSteam.lastPathComponent == "steam")
        }

        /// User profiles win over repo-bundled ones — a player must be able to override a shipped
        /// profile without editing the app bundle.
        @Test("a player's own profiles are searched before the bundled ones")
        func userProfilesWin() throws {
            let paths = Paths.profileSearchPaths.map(\.standardizedFileURL.path)
            let userIndex = try #require(paths.firstIndex(of: Paths.userProfiles.standardizedFileURL.path),
                                         "the user profile directory is not searched at all")
            for (i, path) in paths.enumerated() where i < userIndex {
                #expect(path == Paths.userProfiles.standardizedFileURL.path,
                        "\(path) is searched before the player's own profiles")
            }
        }
    }

    /// Steam's device-authorisation flow is shown to the player as a QR code. DepotDownloader only
    /// draws it in ASCII, so Cellar reads that back and re-renders it — which means the reader is
    /// on the path between "scan this" and the player's phone.
    @Suite("Steam QR reader")
    struct QRTests {
        /// A module is drawn **two characters wide** in the terminal, because a text cell is about
        /// half as wide as it is tall and a QR module has to come out square. Reading one character
        /// per module would halve the width and the code would not scan.
        @Test("a block-drawn row is two characters per module")
        func readsBlocks() {
            #expect(SteamQRCodeReader.modules(in: "██  ██") == [true, false, true])
        }

        @Test("a whitespace row is all light")
        func readsBlank() {
            #expect(SteamQRCodeReader.modules(in: "    ") == [false, false])
        }

        /// The quiet zone that survived the pipe is not part of the code. Cropping to the dark
        /// bounding box is what lets the renderer draw its own margin.
        @Test("the quiet zone is cropped away")
        func cropsQuietZone() throws {
            let rows: [[Bool]] = [
                [false, false, false, false],
                [false, true,  true,  false],
                [false, true,  false, false],
                [false, false, false, false],
            ]
            let trimmed = try #require(SteamQRCodeReader.trimmed(rows))
            #expect(trimmed == [[true, true], [true, false]])
            #expect(SteamQRCodeReader.darkSpan(rows) == 2)
        }

        /// A blank grid must come back as nothing at all. Returning an "empty code" would have the
        /// app render a white square and tell the player to scan it.
        @Test("a grid with no dark modules is not mistaken for a code")
        func rejectsEmptyGrid() {
            var reader = SteamQRCodeReader()
            for _ in 0..<8 { _ = reader.consume("                ") }
            #expect(reader.flush() == nil)
            #expect(SteamQRCodeReader.darkSpan([[false, false], [false, false]]) == nil)
        }
    }
}
