import CellarDomain
import SwiftUI

/// The cover Cellar draws when nobody hands it one.
///
/// Steam publishes free key art for every AppID; Battle.net publishes none that a launcher may
/// hotlink. Rather than let half the library render as empty grey boxes, Cellar composes its own:
/// a deterministic two-tone gradient keyed on the game's name, the title's monogram, and the store's
/// mark. Deterministic matters — a cover that changed hue between launches would read as a bug.
public struct GeneratedCover: View {
    let title: String
    let store: GameStore
    /// The art's short edge, used to scale everything else so one view serves 34pt and 92pt.
    let width: CGFloat

    public init(title: String, store: GameStore, width: CGFloat) {
        self.title = title
        self.store = store
        self.width = width
    }

    public var body: some View {
        ZStack {
            LinearGradient(colors: [base.opacity(0.95), deep], startPoint: .topLeading, endPoint: .bottomTrailing)
            // A soft highlight off the top-left keeps the flat gradient from looking like a swatch.
            RadialGradient(colors: [.white.opacity(0.22), .clear],
                           center: .topLeading, startRadius: 0, endRadius: width * 1.6)
            Text(monogram)
                .font(.system(size: width * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.35), radius: width * 0.03, y: width * 0.01)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, width * 0.1)
        }
        .overlay(alignment: .bottom) {
            // Only large enough covers get the store mark spelled out; on a 34pt sidebar thumbnail
            // it would be mud, and the row prints the store in words anyway.
            if width >= 70 {
                StoreMark(store: store, size: width * 0.15)
                    .opacity(0.9)
                    .padding(.bottom, width * 0.08)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(store.displayName)")
    }

    private var monogram: String {
        // Initials of the first two significant words: "Diablo IV" -> "DI", "Planet Coaster 2" -> "PC".
        let skip: Set<String> = ["the", "of", "a", "an"]
        let initials = title
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { !skip.contains($0.lowercased()) }
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        return initials.isEmpty ? "?" : initials
    }

    /// Stable across launches: Swift's `hashValue` is seeded per process, so hashing the title with
    /// it would repaint the library every time the app opened.
    private var hue: Double {
        let sum = title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 3600 }
        return Double(sum) / 3600.0
    }

    private var base: Color { Color(hue: hue, saturation: 0.52, brightness: 0.62) }
    private var deep: Color { Color(hue: (hue + 0.06).truncatingRemainder(dividingBy: 1),
                                    saturation: 0.72, brightness: 0.30) }
}
