import CellarDomain
import SwiftUI

/// The store's mark and name, side by side — the canonical lockup. Used in section headers and
/// under a game's title so the same pairing is learned once and recognised everywhere.
public struct StoreLockup: View {
    let store: GameStore
    var compact: Bool

    public init(store: GameStore, compact: Bool = false) {
        self.store = store
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            StoreMark(store: store, size: compact ? 11 : 14)
            Text(store.displayName)
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
        }
        .foregroundStyle(store.tint)
        .padding(.horizontal, compact ? 6 : 9)
        .padding(.vertical, compact ? 2 : 4)
        .background(store.tint.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("From \(store.displayName)")
    }
}
