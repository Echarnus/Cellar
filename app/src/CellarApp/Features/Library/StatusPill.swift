import CellarDomain
import SwiftUI
import AppKit
import CellarData
import CellarUI

struct StatusPill: View {
    let game: GameSummary
    /// What Cellar is doing with the game now, which outranks its state on disk: a game being
    /// downloaded is not "Installed" because its exe has landed, nor "Not installed" at 90%.
    var activity: GameActivity? = nil
    var compact = false

    private var text: String { activity?.statusText ?? game.statusText }
    private var tint: Color { activity == nil ? game.statusTint : .accentColor }

    var body: some View {
        if compact {
            Text(text).font(.caption2).foregroundStyle(tint).monospacedDigit()
        } else {
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(tint, in: Capsule())
        }
    }
}
