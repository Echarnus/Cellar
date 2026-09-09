import SwiftUI
import CellarKit

/// One window for "who am I signed in as" — the change that makes signing in a thing you do once.
///
/// Before this, sign-in was a per-game step: the library said "Sign in" on a game, you signed in
/// inside that bottle's Steam, and the next game asked again. Two things fixed that — one shared
/// Steam install behind every bottle, and stores whose token Cellar holds itself (GOG). Both are
/// account-level facts, so they get an account-level screen.
///
/// The rows themselves live in `StoreSignInPanel`, because the first-run tour shows the same ones:
/// a new player signs in during the tour, and comes back here to change it later.
///
/// A separate `NSWindow`, never a `.sheet`: a sheet in the hosted view tree is a fatal
/// AttributeGraph cycle under `NSHostingView` (see skills/swift.md).
struct AccountsView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            StoreSignInPanel()
            Divider()
            footer
        }
        // A *fixed* size, and the window is not resizable — same as Settings, which is the one
        // auxiliary window in this app that has never crashed. A flexible root frame inside
        // NSHostingView lets layout feed back into the view graph, and this app aborts in
        // AttributeGraph when that happens (skills/swift.md). Not worth being clever about.
        .frame(width: 560, height: 620)
        .background(.background)
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Accounts").font(.title2.weight(.semibold))
            Text("Sign in once per store. Cellar shows only what it can actually check.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done", action: onClose).keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }
}
