import AppKit
import SwiftUI
import CellarKit
import CellarUI

/// The window a game starts in.
///
/// Pressing Play begins a minute or two of work the player cannot see: a store client woken in the
/// background, a launch command handed over, a graphics-layer race survived — sometimes twice. Shown
/// as a spinner beside a button, that reads as a hang. Shown here, it reads as a machine doing a job,
/// with the game's own art on it.
///
/// A window rather than a sheet or an overlay, like Settings and Accounts: a `.sheet` inside the
/// hosted view tree is a fatal AttributeGraph cycle under `NSHostingView` (skills/swift.md), and a
/// top-level window is its own view graph. It is also the honest shape — the launch outlives the
/// screen you started it from.
final class LaunchSplashWindow: NSObject, NSWindowDelegate {
    /// Held for the window's lifetime, since nothing else owns it.
    private static var current: LaunchSplashWindow?

    private var window: NSWindow!

    /// Show the launch window for `game`, following `runner`. Presenting twice reuses the window
    /// rather than stacking two of them — Play is disabled while a launch runs, but a second
    /// "Show progress" must not open a second copy.
    static func present(game: GameSummary, runner: CellarRunner) {
        if let current {
            current.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = LaunchSplashWindow()
        controller.show(game: game, runner: runner)
        current = controller
    }

    /// Whether a launch window is on screen — so the detail pane can offer to bring it back.
    static var isPresented: Bool { current != nil }

    static func dismiss() { current?.close() }

    private func show(game: GameSummary, runner: CellarRunner) {
        // Borderless, so the game's own art runs to the top edge — a titled window keeps a title bar
        // above the content whatever `fullSizeContentView` claims, and a bare strip over the banner
        // is exactly the "assembled from parts" look this window exists to replace. Fixed size, like
        // Settings and Accounts: a resizable window plus a flexible SwiftUI root frame lets layout
        // feed back into the view graph, and this app aborts in AttributeGraph when it does
        // (skills/swift.md).
        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: LaunchSplashView.width, height: LaunchSplashView.height),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear          // the rounded corners are the view's, not a mask
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: LaunchSplashView(
            game: game, runner: runner, onDismiss: { [weak self] in self?.close() }))
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        window?.delegate = nil
        window?.close()
        if LaunchSplashWindow.current === self { LaunchSplashWindow.current = nil }
    }

    func windowWillClose(_ notification: Notification) {
        if LaunchSplashWindow.current === self { LaunchSplashWindow.current = nil }
    }
}

/// A borderless window that can still take the keyboard — AppKit refuses that by default, and
/// without it the launch window's buttons could not be reached by Tab or Escape.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// What the launch window shows: the game, the step Cellar has actually reached, and the way out.
struct LaunchSplashView: View {
    static let width: CGFloat = 560
    static let height: CGFloat = 470

    let game: GameSummary
    @ObservedObject var runner: CellarRunner
    let onDismiss: () -> Void

    @State private var elapsed = 0
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
        .onReceive(tick) { _ in if outcome == .working { elapsed += 1 } }
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
                title: "\(game.name) is running",
                detail: game.needsClientAtRuntime
                    ? "Cellar closes \(game.store.displayName) and the whole layer when you quit."
                    : "Cellar closes the layer when you quit.")
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: 12) {
            OutcomeBlock(symbol: "exclamationmark.triangle.fill", tint: .orange,
                    title: "\(game.name) didn't start",
                    detail: failureDetail)
            Text("Nothing is broken by this — try again, or open the logs to see how far it got.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stopped: some View {
        OutcomeBlock(symbol: "stop.circle.fill", tint: .secondary,
                title: "Launch stopped",
                detail: "Cellar stopped waiting. Anything already open stays open.")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if outcome == .working {
                Text(waitingText).font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Waiting \(elapsed) seconds so far.")
            }
            Spacer(minLength: 0)
            if outcome == .failed {
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
            ? "Windows games take a minute or two to come up."
            : "\(clock) so far — Windows games take a minute or two to come up."
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

    private var sequence: [LaunchStage] { LaunchStage.sequence(game.launchContext) }

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
    /// comes back as `Unknown option '--machine-progress'`, which is true and useless — so it is
    /// translated into the thing that actually needs doing.
    private var failureDetail: String {
        if runner.log.contains("Unknown option '--machine-progress'") {
            return "Cellar's command-line tool on this Mac is older than the app, so it doesn't understand this launch. Reinstalling Cellar updates both."
        }
        return lastError.isEmpty
            ? "Cellar stopped before the game came up. The activity log on the game's page has the detail."
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

    private func dismiss(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { onDismiss() }
    }
}

/// One step of the launch: where it stands, what it is called, and — when it is the one happening —
/// what that actually means.
struct LaunchStepRow: View {
    enum State { case done, current, pending }

    let stage: LaunchStage
    let context: LaunchContext
    let state: State
    let detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            marker.frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(stage.title(context))
                    .font(.callout.weight(state == .current ? .semibold : .regular))
                    .foregroundStyle(state == .pending ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spokenState). \(stage.title(context)).\(detail.map { " " + $0 } ?? "")")
    }

    /// Mark and word, never colour alone (skills/ux.md): a ✓ for done, a spinner for the step in
    /// progress, an open circle for one not started.
    @ViewBuilder private var marker: some View {
        switch state {
        case .done:    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .current: ProgressView().controlSize(.small).scaleEffect(0.7)
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary).font(.caption)
        }
    }

    private var spokenState: String {
        switch state {
        case .done:    return "Done"
        case .current: return "In progress"
        case .pending: return "Not started"
        }
    }
}

/// How a launch ended, said in one block: a mark, a headline, and a sentence.
private struct OutcomeBlock: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}
