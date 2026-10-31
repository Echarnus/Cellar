import CellarDomain
import SwiftUI
import AppKit

/// Resolved store artwork, looked up once per store and kept for the life of the process.
///
/// `StoreMark` renders in every library row, so this has to be a dictionary lookup by the second
/// call. The first call touches the filesystem — a handful of `fileExists` checks, and at most one
/// `sips` conversion the very first time a bottle's `.ico` is seen. That happens once ever, not
/// once per launch, because the converted PNG is cached on disk by the engine.
///
/// Finding the file is the engine's job, behind the domain's `StoreArtworkSource` port: the app's
/// composition root calls `use(_:)` once at start-up. Until it does, every store draws Cellar's own
/// vector mark, which is also what a test or a preview gets.
@MainActor
public enum StoreIcons {
    private static var cache: [GameStore: NSImage?] = [:]
    private static var source: (any StoreArtworkSource)?

    /// Where to look for the stores' own icons. Forgets anything already resolved.
    public static func use(_ source: any StoreArtworkSource) {
        self.source = source
        cache.removeAll()
    }

    public static func image(for store: GameStore) -> NSImage? {
        if let known = cache[store] { return known }
        let image = source?.markFile(for: store).flatMap { NSImage(contentsOf: $0) }
        cache[store] = image
        return image
    }

    /// Forget what was resolved, so a store that has just been installed starts showing its own
    /// mark without a relaunch. Called when the library reloads after `cellar setup`.
    public static func refresh() { cache.removeAll() }
}
