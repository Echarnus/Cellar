import CellarDomain
import AppKit
import SwiftUI
import CellarData
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
    /// `onFinished` runs when a launch started from this window ends — a retry on another backend —
    /// so the page behind it can pick up what changed.
    static func present(game: GameSummary, runner: ActivityStore, onFinished: @escaping @MainActor () -> Void = {}) {
        if let current {
            current.window.makeKeyAndOrderFront(nil)
            NSApp.bringToFront()
            return
        }
        let controller = LaunchSplashWindow()
        controller.show(game: game, runner: runner, onFinished: onFinished)
        current = controller
    }

    /// Whether a launch window is on screen — so the detail pane can offer to bring it back.
    static var isPresented: Bool { current != nil }

    static func dismiss() { current?.close() }

    private func show(game: GameSummary, runner: ActivityStore, onFinished: @escaping @MainActor () -> Void) {
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
            game: game, runner: runner, onFinished: onFinished,
            onDismiss: { [weak self] in self?.close() }))
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.bringToFront()
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
