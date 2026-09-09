import SwiftUI
import CellarKit

/// How a store looks and reads in the app.
///
/// Cellar now speaks to more than one storefront, and the player has to be able to tell — at a
/// glance, from across the room — whether a game comes from Steam or from Battle.net, because the
/// answer changes what the next button does. Three signals carry that, always together:
///
/// 1. **Position** — the library is grouped by store, so a game's neighbours already tell you.
/// 2. **A mark** — the store's own logo, drawn as vectors (see `StoreMark`), on the cover and in
///    the header. A real mark is recognised where a generic glyph has to be read.
/// 3. **A word** — the store's name, spelled out, next to the mark.
///
/// No signal ever stands alone. Steam's and Battle.net's brands are both blue, so colour could
/// never have carried this by itself; and a mark with no label is a puzzle for anyone who has not
/// met it before. Position, mark and word travel together everywhere.
extension GameStore {
    /// The store's accent, from CellarKit's descriptor so the CLI and the app agree.
    public var tint: Color {
        let rgb = descriptor.accentColorComponents
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    public var symbol: String { descriptor.symbolName }
}

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
            .overlay(Circle().strokeBorder(.background.opacity(0.92), lineWidth: diameter * 0.10))
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
            .accessibilityHidden(true)   // the row already says the store in words
    }
}

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
