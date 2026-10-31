import CellarDomain
import SwiftUI
import AppKit
import CellarKit
import CellarUI

struct StatusPill: View {
    let game: GameSummary
    var compact = false

    var body: some View {
        if compact {
            Text(game.statusText).font(.caption2).foregroundStyle(game.statusTint)
        } else {
            Text(game.statusText).font(.caption.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(game.statusTint, in: Capsule())
        }
    }
}
