import CellarDomain
import SwiftUI
import AppKit

/// Valve's mark: the valve wheel, the smaller wheel, and the handle that runs out to the rim, on
/// the dark navy Steam has used since 2013.
///
/// The layout is not a matter of taste, and getting it wrong is the tell that a logo was drawn from
/// memory: the **big wheel sits upper-right**, the **small wheel lower-left**, and the handle carries
/// on up past the small wheel to the left rim. Both wheels are open **rings** — draw them as discs
/// with a pinhole and the mark reads as a dumbbell instead of a valve.
///
/// The proportions below were measured off Steam's own `Steam.icns`, in fractions of the mark's box,
/// so they hold at every size. What has to survive the smallest use (11pt in a filter chip) is the
/// big wheel's hole, which is what sets the rest.
struct SteamMark: View {
    let size: CGFloat

    private var navy: Color { Color(.sRGB, red: 0.10, green: 0.16, blue: 0.22, opacity: 1) }

    private let bigWheel = CGPoint(x: 0.655, y: 0.355)
    private let smallWheel = CGPoint(x: 0.330, y: 0.672)
    /// Where the handle runs out to — the left rim, level with the centre. The disc clips it there,
    /// which is what gives the end the flat cut Valve's has.
    private let handleEnd = CGPoint(x: 0.02, y: 0.500)

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [Color(.sRGB, red: 0.16, green: 0.24, blue: 0.33, opacity: 1), navy],
                               startPoint: .topLeading, endPoint: .bottomTrailing))

            // One white silhouette, built by overlapping opaque pieces — the two wheels' holes are
            // then punched back out in navy on top.
            ZStack {
                MarkLine(from: bigWheel, to: smallWheel)
                    .stroke(.white, style: StrokeStyle(lineWidth: size * 0.155, lineCap: .round))
                MarkLine(from: smallWheel, to: handleEnd)
                    .stroke(.white, style: StrokeStyle(lineWidth: size * 0.108, lineCap: .round))

                MarkDisc(center: bigWheel, radius: 0.208).fill(.white)
                MarkDisc(center: smallWheel, radius: 0.115).fill(.white)
                MarkDisc(center: bigWheel, radius: 0.120).fill(navy)
                MarkDisc(center: smallWheel, radius: 0.060).fill(navy)
            }
            .clipShape(Circle())
        }
        .frame(width: size, height: size)
    }
}
