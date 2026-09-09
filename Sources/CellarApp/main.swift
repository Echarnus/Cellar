import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by the "Settings…" menu item; ContentView opens its settings sheet on receipt.
    static let cellarOpenSettings = Notification.Name("cellar.openSettings")
    /// Posted by the "Accounts…" menu item, the sidebar button, and any "Sign in" button for a store
    /// whose token Cellar holds — because that sign-in is account-level, not per-game.
    static let cellarOpenAccounts = Notification.Name("cellar.openAccounts")
}

// A SwiftPM executable can't use @main App scenes, so stand the app up by hand: an NSApplication
// whose window hosts the SwiftUI ContentView. This is the Phase-3 "Steam-like" front-end over
// CellarKit — choose a game, see its state, and play it, with the game's own icon.
//
// Because there is no App scene, AppKit installs no default menu bar — so we build one ourselves
// (⌘Q to quit, About, Settings…, and the Edit menu that text fields need for cut/copy/paste).
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()

        // The gear button in the SwiftUI sidebar asks for Settings via this notification (the menu
        // item calls showSettings directly). Settings is a separate NSWindow, not a SwiftUI .sheet:
        // a sheet presented inside the hosted view triggers a fatal AttributeGraph cycle under
        // NSHostingView. A top-level window is its own view graph, so it's safe.
        NotificationCenter.default.addObserver(
            self, selector: #selector(showSettings), name: .cellarOpenSettings, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(showAccounts), name: .cellarOpenAccounts, object: nil)

        let window = NSWindow(
            // Comfortably above ContentView's minimum: at the minimum the detail pane's two
            // information columns collapse into one, which is a fallback, not the intended look.
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
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

    // MARK: - Menu

    private func buildMainMenu() -> NSMenu {
        let appName = "Cellar"
        let mainMenu = NSMenu()

        // App menu (its bold title comes from CFBundleName once wrapped as Cellar.app).
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(showAbout), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Account…", action: #selector(showAccounts), keyEquivalent: "A")
            .target = self
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu — text fields (the library search box) need these for cut/copy/paste/select-all.
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Window menu.
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 680),
                // Not resizable: a resizable window plus a flexible SwiftUI root frame lets layout
                // feed back into the view graph, and this app aborts in AttributeGraph when it does
                // (skills/swift.md).
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Settings"
            w.isReleasedWhenClosed = false
            w.center()
            w.contentView = NSHostingView(rootView: SettingsView(onClose: { [weak self] in
                self?.settingsWindow?.close()
            }))
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// There is one place to sign in, and it is Settings. "Accounts…" and every "Sign in" button
    /// in the app land on the same window rather than on a second one that could disagree with it.
    @objc private func showAccounts() { showSettings() }

    @objc private func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let credits = NSAttributedString(
            string: "Run Windows games on Apple Silicon — a Proton-like layer over Wine + D3DMetal.\n" +
                    "Sign in once, then install and play the games you own.",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Cellar",
            .applicationVersion: version,
            .credits: credits,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
