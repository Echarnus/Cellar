import CellarDomain
import SwiftUI
import AppKit
import CellarData
import CellarUI

/// Remote image with a graceful fallback. `AsyncImage` handles fetching, `URLCache` the caching.
/// The fallback is shown immediately while loading rather than a spinner over emptiness — for a
/// store with no CDN the fallback *is* the artwork, and it should never flash.
///
/// The image is drawn through `GameArt`, so it keeps its own proportions in a slot of any shape:
/// filled and cropped by default, never stretched (#163).
struct RemoteArt<Fallback: View>: View {
    let url: URL?
    var mode: ContentMode = .fill
    var alignment: Alignment = .center
    let fallback: Fallback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(_ url: URL?, mode: ContentMode = .fill, alignment: Alignment = .center,
         @ViewBuilder fallback: () -> Fallback) {
        self.url = url; self.mode = mode; self.alignment = alignment; self.fallback = fallback()
    }

    var body: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: reduceMotion ? nil : .easeOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let image): GameArt(image, mode: mode, alignment: alignment)
                default: fallback
                }
            }
        } else {
            fallback
        }
    }
}
