import AppKit
import CellarKit
import SwiftUI
import CellarKit

extension Notification.Name {
    /// Posted by the "Settings…" menu item; ContentView opens its settings sheet on receipt.
    static let cellarOpenSettings = Notification.Name("cellar.openSettings")
    /// Posted by the "Accounts…" menu item, the sidebar button, and any "Sign in" button for a store
    /// whose token Cellar holds — because that sign-in is account-level, not per-game.
    static let cellarOpenAccounts = Notification.Name("cellar.openAccounts")
    /// Posted by Settings' "Review folder access…" button — the same window first run shows, in its
    /// status-board form.
    static let cellarOpenFolderAccess = Notification.Name("cellar.openFolderAccess")
    /// Posted by the "Welcome to Cellar…" menu item and by Settings, to replay the first-run tour.
    /// Named for the *tour* specifically, because the folder-access screen above is the other
    /// first-run window and the two coexist rather than fight for the name.
    static let cellarOpenWelcomeTour = Notification.Name("cellar.openWelcomeTour")
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
    var accountsWindow: NSWindow?
    var folderAccessWindow: NSWindow?
    var welcomeTourWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First thing, before anything can crash: this is also where a previous session that
        // never reached applicationWillTerminate gets noticed and written down.
        Diagnostics.processDidStart(version: Bundle.main.shortVersion)
        NSApp.mainMenu = buildMainMenu()

        // The gear button in the SwiftUI sidebar asks for Settings via this notification (the menu
        // item calls showSettings directly). Settings is a separate NSWindow, not a SwiftUI .sheet:
        // a sheet presented inside the hosted view triggers a fatal AttributeGraph cycle under
        // NSHostingView. A top-level window is its own view graph, so it's safe.
        NotificationCenter.default.addObserver(
            self, selector: #selector(showSettings), name: .cellarOpenSettings, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(showAccounts), name: .cellarOpenAccounts, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(showFolderAccess), name: .cellarOpenFolderAccess, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(showWelcomeTour), name: .cellarOpenWelcomeTour, object: nil)

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

        // Two things want the first launch, so they take it in turn — stacking two windows on a
        // player who has not seen the app yet is worse than either on its own.
        //
        // The tour goes first: it introduces Cellar and offers to sign in, before the player is
        // left staring at a library of games that all say "Sign in". Skipping it counts as seen —
        // Settings replays it. Deferred to the next runloop turn so it opens over a window that has
        // already finished its first layout, rather than during it (skills/swift.md).
        //
        // The folder ask then arrives on the next launch, with a sentence explaining it, rather
        // than letting macOS raise it mid-install on behalf of a game (see `HomeFolderAccess`).
        // Settings can raise either one at any time.
        if WelcomeTour.isOwed && !useDiagnostic {
            DispatchQueue.main.async { [weak self] in self?.showWelcomeTour() }
        } else if !HomeFolderAccess.hasAsked {
            showWelcome()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Clears the marker `processDidStart` looks for. Quitting cleanly is how the next start knows
    /// the last one didn't.
    func applicationWillTerminate(_ notification: Notification) {
        Diagnostics.processWillExit()
    }

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
        appMenu.addItem(withTitle: "Welcome to \(appName)…", action: #selector(showWelcomeTour), keyEquivalent: "")
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

    /// The first-run ask. Same window as `showFolderAccess`, but in the form that actually requests
    /// the permissions instead of reporting on them.
    private func showWelcome() { presentFolderAccess(isReview: false) }

    @objc private func showFolderAccess() { presentFolderAccess(isReview: true) }

    private func presentFolderAccess(isReview: Bool) {
        // Rebuilt each time rather than cached: the window has two forms (ask / status board) and a
        // reused NSHostingView would keep the first one's state.
        folderAccessWindow?.close()
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
            // Not resizable, matching Settings and Accounts: a resizable window plus a flexible
            // SwiftUI root frame lets layout feed back into the view graph, and this app aborts in
            // AttributeGraph when it does (skills/swift.md).
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = isReview ? "Folder access" : "Welcome to Cellar"
        w.isReleasedWhenClosed = false
        w.center()
        w.contentView = NSHostingView(rootView: WelcomeView(isReview: isReview) { [weak self] in
            self?.folderAccessWindow?.close()
        })
        folderAccessWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The first-run tour. Its own window for the usual reason — a sheet under `NSHostingView` is a
    /// fatal AttributeGraph cycle — and not resizable, because the tour is laid out at a fixed size.
    /// Closing it by any route (Continue to the end, "Skip for now", or the red button) counts as
    /// seen, so it never reappears uninvited.
    @objc private func showWelcomeTour() {
        if welcomeTourWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 580),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Welcome to Cellar"
            w.isReleasedWhenClosed = false
            w.center()
            w.contentView = NSHostingView(rootView: WelcomeTourView(onFinish: { [weak self] in
                WelcomeTour.markSeen()
                self?.welcomeTourWindow?.close()
            }))
            welcomeTourWindow = w
        }
        WelcomeTour.markSeen()
        welcomeTourWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Cellar",
            .applicationVersion: version,
            .credits: Self.aboutCredits(),
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The About panel's credits: the tagline, then the thank-you to Wine — the project Cellar is a
    /// thin layer over. Short on purpose: the standard panel shows credits in a ~100 pt box that
    /// auto-scrolls when the text overflows, and a long list scrolls Wine straight out of view.
    /// The full list, one link per project, is Settings › About. The GPL / non-affiliation line is
    /// the panel's copyright field (Info.plist), so it is not repeated here.
    private static func aboutCredits() -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11),
                                                    .foregroundColor: NSColor.secondaryLabelColor]
        let heading: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 11),
                                                       .foregroundColor: NSColor.labelColor]
        func link(_ text: String, _ url: URL) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11), .link: url])
        }

        let out = NSMutableAttributedString(string: Credits.tagline + "\n\n", attributes: body)
        out.append(NSAttributedString(string: "Built on Wine. ", attributes: heading))
        out.append(NSAttributedString(string: Credits.wine.role + " ", attributes: body))
        out.append(link("winehq.org", Credits.wine.url))
        out.append(NSAttributedString(string: " · ", attributes: body))
        out.append(link("source", Credits.wine.sourceURL!))
        out.append(NSAttributedString(string: "\n\nEveryone else Cellar stands on: Settings › About.", attributes: body))
        return out
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

extension Bundle {
    /// The version shown in About and written into the log; falls back to the library's own
    /// version when the app runs unwrapped during development.
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? CellarVersion.current
    }
}
