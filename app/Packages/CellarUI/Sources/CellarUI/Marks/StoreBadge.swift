import CellarDomain
import SwiftUI
import CellarKit

/// The store's mark alone, as a badge pinned to a cover. Sized to stay legible at 34pt art without
/// swallowing it, and ringed so it survives whatever the artwork is doing underneath.
public struct StoreBadge: View {
    let store: GameStore
    var diameter: CGFloat

    public init(store: GameStore, diameter: CGFloat = 16) {
        self.store = store
        self.diameter = diameter
    }

    public var body: some View {
        StoreMark(store: store, size: diameter)
            // The ring has to follow the mark's own outline: GOG's is a rounded tile, and a circle
            // drawn round a square reads as a mistake rather than as a badge.
            .overlay(StoreMark.outline(of: store, size: diameter)
                .strokeBorder(.background.opacity(0.92), lineWidth: diameter * 0.10))
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
            .accessibilityHidden(true)   // the row already says the store in words
    }
}
