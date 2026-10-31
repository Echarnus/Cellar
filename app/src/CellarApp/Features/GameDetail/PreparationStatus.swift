import CellarDomain
import AppKit
import SwiftUI
import CellarData

/// The library's footer line while preparation runs: a small spinner and what is happening, with
/// the why on hover. Nothing at all once it is done — there is nothing left to say.
struct PreparationStatus: View {
    let preparation: RuntimePreparation

    var body: some View {
        if case .working(let line) = preparation.state {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Getting ready: \(line)")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .help("Cellar is downloading the Windows runtime and Steam client every game shares, so your first game starts sooner. You can play while it runs; a game that needs them waits for it.")
            .accessibilityElement(children: .combine)
        }
    }
}
