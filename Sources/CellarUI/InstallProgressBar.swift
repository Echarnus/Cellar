import SwiftUI
import CellarKit

/// How far an install has got: which step, and — where Cellar can measure it — how much of it.
///
/// A step with no honest denominator (building a bottle, a silent installer) gets a moving sweep
/// rather than a made-up percentage. The title comes from the phase, not from scraping the CLI's
/// prose, so rewording a progress line cannot break it.
///
/// Lives in CellarUI so the snapshot tests can draw it without launching the app — which is also
/// why the bar is drawn here rather than being a `ProgressView`: that one is AppKit underneath, and
/// `ImageRenderer` cannot draw it.
public struct InstallProgressBar: View {
    let game: String
    let store: GameStore
    let progress: InstallProgress?

    public init(game: String, store: GameStore, progress: InstallProgress?) {
        self.game = game
        self.store = store
        self.progress = progress
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.callout.weight(.medium)).lineLimit(1)
                Spacer(minLength: 8)
                Text(percent).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Track(fraction: progress?.fraction, tint: store.tint)
                .frame(height: 6)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: 340)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(percent.isEmpty ? "In progress" : percent)
    }

    var title: String {
        progress?.phase.title(game: game, store: store) ?? "Getting ready"
    }

    var detail: String {
        progress?.phase.detail(store: store) ?? "Checking what this game still needs."
    }

    /// Rounded down, so the bar never claims 100% while the last bytes are still arriving.
    var percent: String {
        guard let fraction = progress?.fraction else { return "" }
        return "\(Int((fraction * 100).rounded(.down)))%"
    }
}

/// The bar itself: a filled share when there is one, a sweep when there isn't.
///
/// The sweep is positioned from the clock by a `TimelineView` rather than animated with
/// `.animation` — this sits in the app's detail pane, where an animation modifier is the known
/// AttributeGraph crash (skills/swift.md). Both layers are always present so the view tree keeps
/// one shape whichever phase is showing.
private struct Track: View {
    let fraction: Double?
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(tint)
                    .frame(width: max(width * (fraction ?? 0), fraction == nil || fraction == 0 ? 0 : 6))
                    .opacity(fraction == nil ? 0 : 1)
                TimelineView(.animation(minimumInterval: 1 / 30, paused: fraction != nil)) { context in
                    let segment = width * 0.28
                    let phase = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.4) / 1.4
                    Capsule().fill(tint)
                        .frame(width: segment)
                        .offset(x: -segment + (width + segment) * phase)
                }
                .opacity(fraction == nil ? 1 : 0)
            }
            .clipShape(Capsule())
        }
    }
}
