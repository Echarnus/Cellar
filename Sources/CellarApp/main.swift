import AppKit
import SwiftUI

// A SwiftPM executable can't use @main App scenes, so stand the app up by hand: an NSApplication
// whose window hosts the SwiftUI ContentView. This is the Phase-3 "Steam-like" front-end over
// CellarKit — choose a game, see its state, and play it, with the game's own icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Cellar"
        window.center()
        let useDiagnostic = ProcessInfo.processInfo.environment["CELLAR_DIAG"] != nil
        window.contentView = useDiagnostic
            ? NSHostingView(rootView: AnyView(Text("Cellar GUI works").padding()))
            : NSHostingView(rootView: ContentView())
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
