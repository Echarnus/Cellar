import AppKit
import CellarDomain
import Foundation
import Testing
import CellarUI

/// Store icons come in through the domain's `StoreArtworkSource` port (#133): CellarUI never reads
/// the engine, and with no source wired in, every store draws Cellar's own mark.
@MainActor
@Suite(.serialized)
struct StoreIconsTests {

    struct FixedArtwork: StoreArtworkSource {
        let file: URL?
        func markFile(for store: GameStore) -> URL? { file }
    }

    /// A real one-pixel PNG on disk, so the image path is the one the app takes.
    private func pngFile() throws -> URL {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
        let data = try #require(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-icon-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    @Test("A source with nothing installed leaves every store to Cellar's own mark")
    func noArtwork() {
        StoreIcons.use(FixedArtwork(file: nil))
        for store in GameStore.allCases {
            #expect(StoreIcons.image(for: store) == nil)
        }
    }

    @Test("A source that finds the store's own icon hands it to the mark, and refresh asks again")
    func installedArtwork() throws {
        let file = try pngFile()
        defer { try? FileManager.default.removeItem(at: file) }
        StoreIcons.use(FixedArtwork(file: file))
        #expect(StoreIcons.image(for: .steam) != nil)
        // Cached: a second ask is the same answer without touching the disk.
        #expect(StoreIcons.image(for: .steam) != nil)
        try FileManager.default.removeItem(at: file)
        StoreIcons.refresh()
        #expect(StoreIcons.image(for: .steam) == nil)
        StoreIcons.use(FixedArtwork(file: nil))
    }
}
