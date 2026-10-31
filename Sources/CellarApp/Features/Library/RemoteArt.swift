import CellarDomain
import SwiftUI
import AppKit
import CellarKit
import CellarUI

/// Remote image with a graceful fallback. `AsyncImage` handles fetching, `URLCache` the caching.
/// The fallback is shown immediately while loading rather than a spinner over emptiness — for a
/// store with no CDN the fallback *is* the artwork, and it should never flash.
struct RemoteArt<Fallback: View>: View {
    let url: URL?
    let fallback: Fallback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(_ url: URL?, @ViewBuilder fallback: () -> Fallback) { self.url = url; self.fallback = fallback() }

    var body: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: reduceMotion ? nil : .easeOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let image): image.resizable()
                default: fallback
                }
            }
        } else {
            fallback
        }
    }
}
