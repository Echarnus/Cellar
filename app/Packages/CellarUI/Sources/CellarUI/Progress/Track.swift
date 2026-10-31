import CellarDomain
import SwiftUI

/// The bar itself: a filled share when there is one, a sweep when there isn't.
///
/// The sweep is positioned from the clock by a `TimelineView` rather than animated with
/// `.animation` — this sits in the app's detail pane, where an animation modifier is the known
/// AttributeGraph crash (skills/swift.md). Both layers are always present so the view tree keeps
/// one shape whichever phase is showing.
struct Track: View {
    let fraction: Double?
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(Track.trackOpacity(increasedContrast: contrast == .increased)))
                Capsule().fill(tint)
                    .frame(width: max(width * (fraction ?? 0), fraction == nil || fraction == 0 ? 0 : 6))
                    .opacity(fraction == nil ? 0 : 1)
                // With Reduce Motion on, the sweep holds still in the middle of the track: still
                // visibly "working, size unknown", without a block sliding past forever.
                TimelineView(.animation(minimumInterval: 1 / 30, paused: fraction != nil || reduceMotion)) { context in
                    let segment = width * 0.28
                    let phase = Track.sweepPhase(at: context.date, reduceMotion: reduceMotion)
                    Capsule().fill(tint)
                        .frame(width: segment)
                        .offset(x: -segment + (width + segment) * phase)
                }
                .opacity(fraction == nil ? 1 : 0)
            }
            .clipShape(Capsule())
        }
    }

    /// Where the indeterminate sweep sits, 0…1 along the track: moving with the clock, or held
    /// still in the middle when the player has asked for less motion.
    static func sweepPhase(at date: Date, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0.5 }
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
    }

    /// The empty track's strength. Increase Contrast gets a track that is visible on its own, not
    /// one implied by the fill beside it.
    static func trackOpacity(increasedContrast: Bool) -> Double { increasedContrast ? 0.28 : 0.12 }
}
