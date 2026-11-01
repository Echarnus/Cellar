import CellarDomain
import AppKit
import SwiftUI
import CellarData

/// The window behind Troubleshooting → Technical Details: how Cellar runs a game, for whoever is
/// fixing a launch, kept off the game's page so a player who only wants to play never meets it.
///
/// A window rather than a sheet, like the launch window: a `.sheet` inside the hosted view tree is
/// a fatal AttributeGraph cycle under `NSHostingView` (skills/swift.md). Fixed size for the same
/// reason Settings and Accounts are; the content scrolls instead.
final class TechnicalDetailsWindow: NSObject, NSWindowDelegate {
    /// One per game, held for the window's lifetime since nothing else owns it.
    private static var open: [String: TechnicalDetailsWindow] = [:]

    private var window: NSWindow?
    private var slug = ""

    @MainActor
    static func present(game: GameSummary, runner: ActivityStore) {
        if let current = open[game.slug], let window = current.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.bringToFront()
            return
        }
        let controller = TechnicalDetailsWindow()
        controller.show(game: game, runner: runner)
        open[game.slug] = controller
    }

    @MainActor
    private func show(game: GameSummary, runner: ActivityStore) {
        slug = game.slug
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: TechnicalDetailsView.width, height: TechnicalDetailsView.height),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = String(localized: "\(game.name) — Technical Details")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: TechnicalDetailsView(game: game, runner: runner))
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.bringToFront()
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        if TechnicalDetailsWindow.open[slug] === self { TechnicalDetailsWindow.open[slug] = nil }
    }
}
