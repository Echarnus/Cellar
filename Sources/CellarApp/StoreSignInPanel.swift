import SwiftUI
import CellarKit

/// Every store's sign-in row, in one reusable view — the single place that behaviour is written.
///
/// Two screens need it. The **Accounts** window (⌘⇧A) is where a player goes to sign in or out
/// later; the **first-run tour** walks a new player through the same thing before they have ever
/// picked a game. Sharing the view rather than re-typing the copy means the tour cannot promise
/// something the real screen doesn't do — which is the point of the honesty rule in `skills/ux.md`.
///
/// The rows themselves are `AccountsSection`, so there is exactly one definition of what a store's
/// sign-in state *is* and how it is drawn. This adds only what the hosts differ on: the activity
/// strip, and owning the runner and the state snapshot.
///
/// Everything AttributeGraph-sensitive lives here rather than in the hosts: no work in `init`, no
/// disk read from a view body, no view tree that changes shape mid-run (see `skills/swift.md`).
struct StoreSignInPanel: View {
    /// Height of the activity strip, or `nil` to leave it out entirely. Constant per instance —
    /// the tour is tighter for space than the Accounts window, but neither changes its mind
    /// half-way through a run, so the view tree's shape stays fixed.
    var activityHeight: CGFloat? = 108

    @StateObject private var runner = CellarRunner()
    /// Read once per refresh, never from a view body — see `StoreAccountState`.
    @State private var state = StoreAccountState.unknown

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                AccountsSection(runner: runner, state: state, refresh: refresh)
                    .padding(16)
            }
            if let activityHeight {
                Divider()
                activity(height: activityHeight)
            }
        }
        .onAppear(perform: refresh)
    }

    /// What Cellar is doing, in the player's view rather than a hidden terminal. A sign-in runs the
    /// CLI, and a player who can see it working is a player who does not press the button twice.
    private func activity(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small).opacity(runner.busy ? 1 : 0)
                Text(runner.busy ? runner.busyTitle : "Anything Cellar runs shows up here.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(runner.busy ? "Busy, \(runner.busyTitle)" : "Activity")
            ScrollView {
                Text(runner.log.isEmpty ? " " : runner.log)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9).padding(.bottom, 8)
            }
        }
        .frame(height: height)
        .background(Color.primary.opacity(0.04))
    }

    /// This work is not cheap — it stats bottles, reads the keychain, and asks GOG for a username
    /// over the network. Doing it inline in `onAppear` meant blocking the main thread and then
    /// mutating `@State` in the middle of `NSHostingView`'s first layout pass, which re-enters the
    /// view graph and aborts in AttributeGraph.
    private func refresh() {
        Task.detached {
            if GOGAuth.isSignedIn, GOGAuth.cachedUsername == nil {
                GOGAuth.cacheUsername(try? GOGAuth.username())
            }
            let snapshot = StoreAccountState.current()
            await MainActor.run { state = snapshot }
        }
    }
}
