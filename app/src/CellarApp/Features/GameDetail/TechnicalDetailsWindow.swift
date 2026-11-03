import CellarDomain
import AppKit
import SwiftUI
import CellarUI
import CellarData

/// The game's own windows beside its page: Troubleshooting → Technical Details (how Cellar runs a
/// game, for whoever is fixing a launch), and Settings… from the sidebar's right-click menu (the
/// game's display switches, as Steam's Properties… opens beside its library).
///
/// A window rather than a sheet, like the launch window: a `.sheet` inside the hosted view tree is
/// a fatal AttributeGraph cycle under `NSHostingView` (skills/swift.md). Fixed size for the same
/// reason Settings and Accounts are; the content scrolls instead.
final class TechnicalDetailsWindow: NSObject, NSWindowDelegate {
    /// One per game, held for the window's lifetime since nothing else owns it.
    private static var open: [String: TechnicalDetailsWindow] = [:]

    private var window: NSWindow?
    private var key = ""

    @MainActor
    static func present(game: GameSummary, runner: ActivityStore) {
        present(key: game.slug, title: String(localized: "\(game.name) — Technical Details"),
                size: NSSize(width: TechnicalDetailsView.width, height: TechnicalDetailsView.height)) {
            AnyView(TechnicalDetailsView(game: game, runner: runner))
        }
    }

    /// The game's settings on their own, for the sidebar's right-click Settings….
    @MainActor
    static func presentSettings(game: GameSummary) {
        present(key: game.slug + "#settings", title: String(localized: "\(game.name) Settings"),
                size: NSSize(width: GameSettingsView.width, height: GameSettingsView.height)) {
            AnyView(GameSettingsView(game: game))
        }
    }

    @MainActor
    private static func present(key: String, title: String, size: NSSize, content: () -> AnyView) {
        if let current = open[key], let window = current.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.bringToFront()
            return
        }
        let controller = TechnicalDetailsWindow()
        controller.show(key: key, title: title, size: size, content: content())
        open[key] = controller
    }

    @MainActor
    private func show(key: String, title: String, size: NSSize, content: AnyView) {
        self.key = key
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: content.buttonStyle(.hoverAutomatic))
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.bringToFront()
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        if TechnicalDetailsWindow.open[key] === self { TechnicalDetailsWindow.open[key] = nil }
    }
}
