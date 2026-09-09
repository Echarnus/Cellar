import SwiftUI
import AppKit
import CellarKit

/// Whether the first-run tour is owed, and the record that it has been seen.
///
/// Versioned rather than a bool: when the tour gains a step that matters (a new store, a changed
/// sign-in), bumping `version` shows it once more to people who already ran the old one. Skipping
/// counts as seen — a tour that reappears after you dismissed it is nagging, not helping. It can
/// always be replayed from Settings.
enum WelcomeTour {
    /// Bump when the tour teaches something a returning player has not been told.
    static let version = 1
    private static let key = "welcomeTourVersionSeen"

    static var isOwed: Bool { UserDefaults.standard.integer(forKey: key) < version }
    static func markSeen() { UserDefaults.standard.set(version, forKey: key) }
}

/// The first thing a new player sees: what Cellar is, how a game gets running, and — the one step
/// that actually does something — signing in to their stores.
///
/// It is a tour rather than a wall of text because the sign-in step is *live*: it embeds the real
/// `StoreSignInPanel`, so a player who signs in here is genuinely signed in, and one who skips is
/// told, twice and plainly, where to do it later. Nothing here claims a state Cellar can't check
/// (skills/ux.md) — the store rows report exactly what the Accounts window reports.
///
/// A standalone `NSWindow`, never a `.sheet`: a sheet under `NSHostingView` aborts in
/// AttributeGraph (skills/swift.md). Fixed size, non-resizable, and no animation between steps for
/// the same reason.
///
/// Named `WelcomeTourView` rather than `WelcomeView` on purpose: a separate first-run screen that
/// asks for Documents/Desktop/Downloads access is in flight on another branch under the latter name.
/// Both are things a new player meets on first launch, and they should be able to land independently
/// — which order they appear in is a decision to make when the second one merges.
struct WelcomeTourView: View {
    /// Called when the player finishes or skips — the host closes the window and records it.
    let onFinish: () -> Void

    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable, Hashable {
        case welcome, howItWorks, accounts, ready

        var isLast: Bool { self == .ready }
        var next: Step { Step(rawValue: rawValue + 1) ?? self }
        var previous: Step { Step(rawValue: rawValue - 1) ?? self }
    }

    var body: some View {
        VStack(spacing: 0) {
            page
                .frame(width: 620, height: 512)
                // Replace the step's view tree outright rather than letting SwiftUI diff two
                // differently-shaped pages — the same reason GameDetailView carries `.id(slug)`.
                .id(step)
            Divider()
            controls
        }
        .frame(width: 620, height: 580)
        .background(.background)
    }

    @ViewBuilder private var page: some View {
        switch step {
        case .welcome:    welcomePage
        case .howItWorks: howItWorksPage
        case .accounts:   accountsPage
        case .ready:      readyPage
        }
    }

    // MARK: - 1. Welcome

    private var welcomePage: some View {
        // Spacers top and bottom: the page is shorter than the accounts step, and content pinned to
        // the top of a fixed-height window reads as a layout that ran out rather than one at rest.
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 84, height: 84)
                    .accessibilityHidden(true)
                Text("Welcome to Cellar")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Your Windows games, running on this Mac.")
                    .font(.title3).foregroundStyle(.secondary)
            }
            .padding(.top, 34)

            VStack(alignment: .leading, spacing: 14) {
                FactRow(symbol: "cube.transparent", tint: .pink,
                        title: "No Windows, no virtual machine",
                        detail: "Cellar builds a small Windows environment per game — Wine, plus Apple's D3DMetal — and translates the game's graphics to Metal as it runs.")
                FactRow(symbol: "person.badge.shield.checkmark", tint: .blue,
                        title: "Games you already own",
                        detail: "Everything installs from your own Steam, Battle.net or GOG account. Cellar doesn't host, sell or unlock anything.")
                FactRow(symbol: "heart", tint: .red,
                        title: "Free and open source",
                        detail: "GPL-3.0, no account with us, no telemetry. Not affiliated with Valve, Blizzard, GOG or Apple.")
            }
            .padding(.horizontal, 40)
            .padding(.top, 26)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 2. How it works

    private var howItWorksPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeading(title: "How a game gets running",
                        subtitle: "Three steps, in this order. Every game's page tells you which one is next, so there is nothing to remember.")

            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, title: "Sign in to the store",
                        detail: "A game comes from Steam, Battle.net or GOG. One sign-in covers every game from that store — you are not asked again per game.")
                StepRow(number: 2, title: "Set up the game",
                        detail: "Cellar downloads the Wine runner and builds the game its own bottle. The first one takes a few minutes; the ones after are quick.")
                StepRow(number: 3, title: "Play",
                        detail: "Press Play. Cellar starts whatever the game needs alongside it, and shuts all of it down when you quit.")
            }
            .padding(.horizontal, 40)

            Spacer(minLength: 0)

            Text("Some games need their store's client open while they run; some don't. Cellar says which on the game's page rather than surprising you.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40).padding(.bottom, 22)
        }
    }

    // MARK: - 3. Accounts — the step that actually does something

    private var accountsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeading(title: "Sign in to your stores",
                        subtitle: "Sign in once per store and every game from it is ready. You can do this later instead — Settings, or ⌘⇧A — and Cellar works fine until you do.")
            StoreSignInPanel(activityHeight: 78)
                .frame(maxHeight: .infinity)
        }
    }

    // MARK: - 4. Ready

    private var readyPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("You're all set")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Pick a game in the sidebar and Cellar will tell you what it needs next.")
                    .font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 30)

            VStack(alignment: .leading, spacing: 12) {
                FactRow(symbol: "person.crop.circle", tint: .blue,
                        title: "Accounts — sign in any time",
                        detail: "The person icon in the sidebar, ⌘⇧A, or Settings → Manage accounts. Signing in later works exactly as it does here.")
                FactRow(symbol: "gearshape", tint: .gray,
                        title: "Settings — ⌘,",
                        detail: "The Wine runner, your logs and the Cellar folder. It also replays this tour whenever you want it.")
                FactRow(symbol: "questionmark.circle", tint: .purple,
                        title: "Questions",
                        detail: "The supported-games list and the FAQ live on the Cellar site, linked from Settings.")
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Controls

    /// Back, Skip and the step dots are always present — disabled and faded rather than removed —
    /// so the control strip never changes shape between steps.
    private var controls: some View {
        HStack(spacing: 10) {
            Button("Skip for now") {
                onFinish()
            }
            .buttonStyle(.link)
            .disabled(step.isLast)
            .opacity(step.isLast ? 0 : 1)
            .accessibilityHidden(step.isLast)
            .help("Close the tour. You can sign in later from Accounts or Settings.")

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { dot in
                    Circle()
                        .fill(dot == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")

            Spacer(minLength: 0)

            Button("Back") { step = step.previous }
                .disabled(step == .welcome)
            Button(step.isLast ? "Start using Cellar" : "Continue") {
                if step.isLast { onFinish() } else { step = step.next }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .frame(height: 67)
    }
}

// MARK: - Pieces

/// A page's title and its one plain sentence saying what this step is for.
private struct PageHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 40).padding(.top, 30).padding(.bottom, 20)
    }
}

/// One thing worth knowing, as symbol + title + sentence.
private struct FactRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(tint)
                .frame(width: 26, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}

/// A numbered step in the three-step story, in a card so the order reads at a glance.
private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(number)")
                .font(.callout.weight(.bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.pink, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(title). \(detail)")
    }
}
