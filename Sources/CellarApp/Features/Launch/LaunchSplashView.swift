import CellarDomain
import AppKit
import SwiftUI
import CellarKit
import CellarUI

/// What the launch window shows: the game, the step Cellar has actually reached, and the way out.
struct LaunchSplashView: View {
    static let width: CGFloat = 560
    static let height: CGFloat = 470

    let game: GameSummary
    let runner: ActivityStore
    let onFinished: @MainActor () -> Void
    let onDismiss: () -> Void

    @State private var elapsed = 0
    /// Whether this window already retried on the profile's fallback backend. Offered once: a
    /// second failure gets the logs, not another button that leads back to the same place.
    @State private var retriedOnFallback = false
    /// Whether this launch ever asked for a sign-in — a step that has happened stays on the list.
    @State private var sawSignIn = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            VStack(alignment: .leading, spacing: 16) {
                // Centred between the art and the footer, so the window looks composed whether it
                // is showing four steps, a retry notice, or a single line saying the game is up.
                Spacer(minLength: 0)
                switch outcome {
                case .working:   steps
                case .running:   arrived
                case .failed:    failure
                case .cancelled: stopped
                }
                Spacer(minLength: 0)
                footer
            }
            .padding(22)
        }
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .background(.background)
        // The window is borderless and transparent, so the rounded corner is the view's job.
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onReceive(tick) { _ in
            if outcome == .working { elapsed += 1 }
            if runner.stage == .signIn { sawSignIn = true }
        }
        .onChange(of: outcome) { newValue in
            switch newValue {
            // The game is on screen; the window has said what it came to say. A beat, so the ✓ is
            // seen rather than flashed, then out of the way.
            case .running:   dismiss(after: 1.8)
            case .cancelled: dismiss(after: 0.6)
            case .working, .failed: break
            }
        }
    }

    // MARK: - Header

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            GameBanner(game: game)
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.82)],
                           startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 14) {
                GameCover(game: game, width: 62, showsBadge: false)
                VStack(alignment: .leading, spacing: 6) {
                    Text(game.name)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(.white).shadow(radius: 4).lineLimit(2)
                    StoreLockup(store: game.store, compact: true)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .frame(width: Self.width, height: 176)
        .clipped()
    }

    // MARK: - The steps

    /// The launch, step by step. Only the step Cellar has actually reached explains itself — four
    /// paragraphs at once is a wall, and the other three are not what is happening now.
    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(sequence.enumerated()), id: \.element) { index, stage in
                LaunchStepRow(stage: stage,
                              context: game.launchContext,
                              state: state(of: index),
                              detail: state(of: index) == .current ? stage.detail(game.launchContext) : nil)
            }
            // Work the launch has to finish before the game can start — Steam's first update — gets
            // the same bar as Install, instead of Steam's own window appearing over this one.
            if let update = runner.installProgress, (runner.stage ?? .preparing) == .preparing {
                InstallProgressBar(game: game.name, store: game.store, progress: update)
                    .padding(.leading, 26)
            }
            if runner.attempt > 1 {
                Label("Try \(runner.attempt). The first one didn't stick — that is normal here, and Cellar keeps going.",
                      systemImage: "arrow.clockwise")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var arrived: some View {
        OutcomeBlock(symbol: "checkmark.circle.fill", tint: .green,
                title: String(localized: "\(game.name) is running"),
                detail: game.needsClientAtRuntime
                    ? String(localized: "Cellar closes \(game.store.displayName) and the whole layer when you quit.")
                    : String(localized: "Cellar closes the layer when you quit."))
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: 12) {
            OutcomeBlock(symbol: "exclamationmark.triangle.fill", tint: .orange,
                    title: String(localized: "\(game.name) didn't start"),
                    detail: failureDetail)
            if let retry = offeredBackend {
                Text("Its profile names \(retry.displayName) as the one to try when \(currentBackendName) doesn't work. \(retry.summary) If \(game.name) comes up, Cellar keeps using it; you can switch back on the game's page.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Nothing is broken by this — try again, or open the logs to see how far it got.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Only once the game itself was started, and once the fallback has had its turn:
                // "didn't start" about a runner that isn't installed sends the profile's
                // maintainers after the wrong problem.
                if runner.attempt > 0 {
                    Button("Report that it didn't start…") { CompatibilityPrompt.preview(game, outcome: .didNotStart) }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    private var stopped: some View {
        OutcomeBlock(symbol: "stop.circle.fill", tint: .secondary,
                title: String(localized: "Launch stopped"),
                detail: String(localized: "Cellar stopped waiting. Anything already open stays open."))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if outcome == .working {
                Text(waitingText).font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Waiting \(elapsed) seconds so far.")
            }
            Spacer(minLength: 0)
            if outcome == .failed, let retry = offeredBackend {
                Button("Show logs") { NSWorkspace.shared.open(Paths.logs) }
                Button("Close") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Try again with \(retry.displayName)") { retryLaunch(on: retry) }
                    .keyboardShortcut(.defaultAction)
                    .help("Start \(game.name) again on \(retry.displayName). \(retry.summary)")
            } else if outcome == .failed {
                Button("Show logs") { NSWorkspace.shared.open(Paths.logs) }
                Button("Close") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            } else if outcome == .running {
                // This window closes itself a beat from now. The button is here so a borderless
                // window is never a room without a door, whatever happens to that timer.
                Button("Close") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            } else if outcome == .working {
                // Two different things, so two buttons: one leaves the launch alone, one stops it.
                Button("Hide") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("Close this window. \(game.name) keeps starting.")
                Button("Cancel launch") { runner.cancel() }
                    .help("Stop waiting for \(game.name). Anything already open — \(game.store.displayName), the game itself — stays open.")
            }
        }
    }

    private var waitingText: String {
        let clock = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        return elapsed < 20
            ? String(localized: "Windows games take a minute or two to come up.")
            : String(localized: "\(clock) so far — Windows games take a minute or two to come up.")
    }

    // MARK: - State

    private enum Outcome: Equatable { case working, running, failed, cancelled }

    private var outcome: Outcome {
        if runner.busy {
            // `cellar launch` stays alive for the whole session so it can close the layer after.
            // Reaching `playing` is the game being up, not the command being over.
            return runner.phase == .playing ? .running : .working
        }
        if runner.cancelled { return .cancelled }
        if runner.stage == .running || runner.stage == .playing || runner.stage == .closed { return .running }
        return (runner.exitCode ?? 0) == 0 ? .running : .failed
    }

    private var sequence: [LaunchStage] {
        let context = game.launchContext
        // Steam refused the session Cellar handed it, so its window opened after all: show the
        // sign-in step rather than jumping back to the first one — and keep showing it for the rest
        // of the launch, because a checklist that drops a step the player just completed reads as a
        // different launch.
        guard sawSignIn || runner.stage == .signIn, !context.signsInFirst else {
            return LaunchStage.sequence(context)
        }
        return LaunchStage.sequence(LaunchContext(game: context.game, store: context.store,
                                                  throughClient: context.throughClient, signsInFirst: true))
    }

    private func state(of index: Int) -> LaunchStepRow.State {
        // Before the first marker arrives Cellar is, truthfully, on the first step.
        let current = runner.stage.flatMap { sequence.firstIndex(of: $0) } ?? 0
        if index < current { return .done }
        return index == current ? .current : .pending
    }

    /// Why it didn't start, in words the player can act on.
    ///
    /// The app and the `cellar` tool are installed together but can drift apart on a machine where
    /// only one was updated, and the tool then rejects the flag the launch window listens to. That
    /// comes back as `Unknown option '--events'`, which is true and useless — so it is
    /// translated into the thing that actually needs doing.
    private var failureDetail: String {
        if runner.log.contains("Unknown option '--events'") || runner.log.contains("Unknown option '--machine-progress'") {
            return String(localized: "Cellar's command-line tool on this Mac is older than the app, so it doesn't understand this launch. Reinstalling Cellar updates both.")
        }
        return lastError.isEmpty
            ? String(localized: "Cellar stopped before the game came up. The activity log on the game's page has the detail.")
            : lastError
    }

    /// The last thing the CLI said, for the failure state — the error it exits on is the last line
    /// worth reading, and making the player go find the log to see it would be a small cruelty.
    private var lastError: String {
        runner.log
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty && !$0.hasPrefix("(exit ") && !$0.hasPrefix("$ cellar") }
            .map { $0.hasPrefix("Error:") ? String($0.dropFirst("Error:".count)).trimmingCharacters(in: .whitespaces) : $0 }
            ?? ""
    }

    /// The profile's fallback backend, when it is worth offering: the game itself was started (a
    /// runner that isn't installed is not a graphics problem), and this window hasn't tried it yet.
    private var offeredBackend: GraphicsBackend? {
        guard !retriedOnFallback, runner.attempt > 0 else { return nil }
        return game.retryBackend
    }

    private var currentBackendName: String {
        GraphicsBackend(rawValue: game.backend)?.displayName ?? game.backend
    }

    private func retryLaunch(on backend: GraphicsBackend) {
        retriedOnFallback = true
        elapsed = 0
        sawSignIn = false
        runner.launch(slug: game.slug, showHUD: runner.launchShowsHUD, backend: backend) { onFinished() }
    }

    private func dismiss(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { onDismiss() }
    }
}
