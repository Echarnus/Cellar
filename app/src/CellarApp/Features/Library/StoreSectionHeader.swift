import CellarDomain
import SwiftUI
import AppKit
import CellarData
import CellarUI

/// A store's heading in the library. Carries the mark *and* the word, so the section — not each
/// row — is what tells you where these games come from.
struct StoreSectionHeader: View {
    let store: GameStore
    let count: Int
    var guessed = false

    var body: some View {
        HStack(spacing: 6) {
            StoreMark(store: store, size: 13)
            Text(store.descriptor.sectionTitle.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(store.tint)
                .kerning(0.6)
            if guessed {
                Text("· UNTESTED, CELLAR GUESSED")
                    .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    .kerning(0.6).lineLimit(1)
                    .help("Cellar wrote these games' settings itself from their files. Nobody has tested them yet.")
            }
            Text("\(count)")
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 4)
        // The same material as the sidebar under it, so a pinned heading reads as part of the
        // sidebar rather than an opaque strip floating over it.
        .background(SidebarMaterial())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenHeading(store: store.displayName, guessed: guessed, count: count))
    }

    /// Whole sentences per case, so a translation never has to fit English words around a number.
    static func spokenHeading(store: String, guessed: Bool, count: Int) -> String {
        switch (guessed, count == 1) {
        case (false, true):  return String(localized: "\(store), 1 game")
        case (false, false): return String(localized: "\(store), \(count) games")
        case (true, true):   return String(localized: "\(store), untested, settings guessed by Cellar, 1 game")
        case (true, false):  return String(localized: "\(store), untested, settings guessed by Cellar, \(count) games")
        }
    }
}
