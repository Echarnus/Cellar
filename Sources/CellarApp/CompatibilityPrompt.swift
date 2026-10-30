import AppKit
import CellarKit

/// "How did it run?" — asked once per game and setup, after a session ends, and only ever turned
/// into a GitHub issue the player reads first and files themselves (`CompatibilityReport`).
///
/// Alerts rather than a SwiftUI sheet: a `.sheet` inside the hosted view tree is a fatal
/// AttributeGraph cycle under `NSHostingView` (skills/swift.md), and two short questions do not
/// need a window of their own.
@MainActor
enum CompatibilityPrompt {

    /// After the player quits a game. Asked at most once per game for a given Cellar, runner and
    /// backend; "Not now" counts as an answer.
    static func offerAfterSession(_ game: GameSummary) {
        let setup = CompatibilityReport.setupKey(runner: game.runnerID, backend: game.backend)
        guard CompatibilityReport.shouldAsk(slug: game.slug, setup: setup) else { return }
        CompatibilityReport.markAsked(slug: game.slug, setup: setup)

        let alert = NSAlert()
        alert.messageText = "How did \(game.name) run?"
        alert.informativeText = "A short report helps the next person with this game. You'll see exactly what it says before anything leaves your Mac, and you file it yourself on GitHub."
        alert.addButton(withTitle: "It worked")
        alert.addButton(withTitle: "It had problems")
        alert.addButton(withTitle: "Not now")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  preview(game, outcome: .works)
        case .alertSecondButtonReturn: preview(game, outcome: .issues)
        default: break
        }
    }

    /// Show the report word for word, and open GitHub's form with it only if the player says so.
    static func preview(_ game: GameSummary, outcome: CompatibilityReport.Outcome) {
        let facts = CompatibilityReport.Facts(game, outcome: outcome)
        let alert = NSAlert()
        alert.messageText = CompatibilityReport.title(facts)
        alert.informativeText = "This is everything the report says. Opening it shows GitHub's form in your browser with this filled in, and space for what happened. Nothing is sent until you submit it there."
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 130))
        text.string = CompatibilityReport.environment(facts)
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        text.textContainerInset = NSSize(width: 6, height: 6)
        let scroll = NSScrollView(frame: text.frame)
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Open on GitHub")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(CompatibilityReport.issueURL(facts))
    }
}
