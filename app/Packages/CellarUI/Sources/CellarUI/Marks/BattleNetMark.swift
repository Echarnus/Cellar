import CellarDomain
import SwiftUI
import AppKit

/// Blizzard's mark: the Battle.net orb — three tapered orbits crossing around an open centre, on
/// its flat blue.
///
/// The orb is not a spiral, which is the shape it is most often mistaken for (and the shape Cellar
/// drew until it was held next to the real thing). It is three **orbit arcs** at 120° to each other,
/// each a slice of the same flattened ellipse, each swelling from a whisker-thin tail to a blunt
/// head. What makes it read as Battle.net rather than as an atom is that they cross, and that the
/// three inner edges leave a curved triangle open in the middle.
///
/// The disc is flat `#008DE3` — sampled off Blizzard's own mark, which carries no gradient.
struct BattleNetMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(.sRGB, red: 0.0, green: 0.553, blue: 0.890, opacity: 1))

            ForEach([0.0, 120.0, 240.0], id: \.self) { turn in
                OrbitBlade()
                    .fill(.white)
                    .rotationEffect(.degrees(turn))
            }
        }
        .frame(width: size, height: size)
    }
}
