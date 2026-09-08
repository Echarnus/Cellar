import AppKit
import CellarKit

/// The "are you sure" for removing a game — the one place in Cellar where a wrong click costs a
/// player a 36 GB download.
///
/// It is an `NSAlert`, not a SwiftUI `.sheet`: a sheet presented inside the hosted view tree
/// aborts this app in AttributeGraph (skills/swift.md). An alert is its own window, and it is also
/// simply the right control — modal, native, dismissible with Escape.
///
/// The alert never guesses what will be deleted: it shows `Uninstall.plan`, the same plan the CLI
/// prints and then carries out. Measuring it walks the game's directory, so that happens off the
/// main thread and the alert appears when the numbers are real.
enum UninstallConfirmation {

    /// Ask, then hand back the confirmed scope.
    ///
    /// `measured` fires on the main thread the moment the plan is ready — measuring a 36 GB library
    /// takes a few seconds, and a menu item that appears to do nothing for that long reads as broken.
    /// `confirmed` is called only when the player has actually agreed.
    @MainActor
    static func ask(for game: GameSummary, scope: RemovalScope,
                    measured: @escaping () -> Void = {}, confirmed: @escaping () -> Void) {
        guard let plan = try? Game.plan(slug: game.slug) else { measured(); return }

        Task.detached {
            let removal = Uninstall.plan(for: plan, scope: scope)
            await MainActor.run {
                measured()
                present(removal, game: game, confirmed: confirmed)
            }
        }
    }

    @MainActor
    private static func present(_ removal: RemovalPlan, game: GameSummary,
                                confirmed: @escaping () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning

        // Blockers first: a plan can be empty *because* something stopped it being made, and
        // "nothing to remove" in place of "that bottle belongs to two other games" is a lie.
        if let blocker = removal.blockers.first {
            alert.messageText = "Cellar can't remove \(game.name) yet"
            alert.informativeText = blocker
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        if removal.isEmpty {
            alert.alertStyle = .informational
            alert.messageText = "Nothing to remove"
            alert.informativeText = "\(game.name) isn't installed, and Cellar has nothing of its own left on disk."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        alert.messageText = title(for: removal, game: game)
        alert.informativeText = body(for: removal)
        alert.addButton(withTitle: removal.scope == .bottle ? "Remove" : "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        // Return picks Cancel, not the delete. The destructive button stays first, where macOS puts
        // it, but it has to be aimed at deliberately.
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"

        if alert.runModal() == .alertFirstButtonReturn { confirmed() }
    }

    private static func title(for removal: RemovalPlan, game: GameSummary) -> String {
        switch removal.scope {
        case .bottle:
            return "Remove \(game.name) and its bottle?"
        case .game:
            return removal.removesGameFiles
                ? "Uninstall \(game.name)?"
                : "Clean up what's left of \(game.name)?"
        }
    }

    /// What goes, what stays, and anything the player should expect afterwards — the same three
    /// sections the CLI prints, in as few lines as an alert can carry.
    private static func body(for removal: RemovalPlan) -> String {
        var lines: [String] = []
        lines.append(removal.removesGameFiles || removal.scope == .bottle
            ? "Deletes \(removal.totalSizeDescription):"
            : "\(removal.name) isn't installed. Deletes \(removal.totalSizeDescription) of leftovers:")
        for item in removal.items.prefix(5) {
            lines.append(item.kind == .steamShortcut
                ? "• \(item.label)"
                : "• \(item.label) — \(ByteSize.describe(item.bytes))")
        }
        if removal.items.count > 5 {
            lines.append("• and \(removal.items.count - 5) more")
        }
        if !removal.kept.isEmpty {
            lines.append("")
            lines.append("Keeps:")
            for line in removal.kept { lines.append("• \(line)") }
        }
        for warning in removal.warnings {
            lines.append("")
            lines.append(warning)
        }
        return lines.joined(separator: "\n")
    }
}
