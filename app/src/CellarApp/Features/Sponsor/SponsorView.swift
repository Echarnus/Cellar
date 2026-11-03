import CellarDomain
import SwiftUI
import AppKit
import CellarData
import CellarUI

/// Sponsoring, said once and plainly: Cellar is free, nothing is held back, and the money buys
/// Macs to test games on.
///
/// Shown uninvited only once (`SponsorInvite`), after the player has played a game; any time from
/// the app menu. One action — open the site's sponsor page — and a way out that is never a guilt
/// trip. A separate fixed-size `NSWindow` like the tour, never a sheet (skills/swift.md).
struct SponsorView: View {
    /// Shown by Cellar rather than asked for: the way out reads "Not Now" instead of "Close".
    let invited: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 16) {
                FactRow(symbol: "laptopcomputer", tint: .pink,
                        title: String(localized: "A Mac of every kind"),
                        detail: String(localized: "A game can run well on an M4 Max and struggle on an M1. Testing on each chip is how Cellar can tell you which Mac a game needs, from a real run instead of a guess."))
                FactRow(symbol: "lock.open", tint: .green,
                        title: String(localized: "Nothing is locked"),
                        detail: String(localized: "Sponsoring unlocks nothing and removes nothing. Cellar works exactly the same whether you give or not."))
                FactRow(symbol: "list.bullet.rectangle", tint: .blue,
                        title: String(localized: "Out in the open"),
                        detail: String(localized: "The sponsor page lists what the money is for and every Mac it has bought."))
            }
            .padding(.horizontal, 40)
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: 520, height: 440)
        .background(.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                KegMark(size: 18).foregroundStyle(.pink)
                Text("Help Cellar Test on More Macs").font(.title2.weight(.semibold))
            }
            Text("Cellar is free and stays free, for everyone. What it can’t do for free is buy the Macs games are tested on.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 40).padding(.top, 30).padding(.bottom, 24)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Opens the Cellar website.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(invited ? String(localized: "Not Now") : String(localized: "Close"), action: onClose)
                .keyboardShortcut(.cancelAction)
            Button("Sponsor Cellar") {
                NSWorkspace.shared.open(Sponsorship.pageURL)
                onClose()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}
