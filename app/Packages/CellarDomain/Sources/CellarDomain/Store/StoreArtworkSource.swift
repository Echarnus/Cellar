import Foundation

/// Where a store's own icon is on this Mac, if anywhere — the port the UI asks, so a view never
/// reads the disk itself.
///
/// Cellar never bundles a store's logo: it points at the copy the player already has (the Mac
/// app's `.icns`, the icon Wine extracted from the Windows client, a loose `.ico`). Finding that
/// copy is I/O, which belongs to the engine (`InstalledStoreArtwork`); the UI library only holds
/// the protocol and draws its own vector mark when the answer is nil.
public protocol StoreArtworkSource: Sendable {
    /// A file the UI can load as an image, or nil to draw Cellar's own mark instead.
    func markFile(for store: GameStore) -> URL?
}
