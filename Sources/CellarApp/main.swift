import AppKit
import CellarKit
import SwiftUI

/// What is left of the app's notifications: windows asking `AppDelegate` to open other windows,
/// and ⌘F reaching a view's focus. State changes are not here — they are calls on the stores
/// `AppModel` owns (docs/APP-ARCHITECTURE.md).
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
    /// Posted by Edit › Find… (⌘F), so the keyboard reaches the library search like any Mac app's.
    static let cellarFocusSearch = Notification.Name("cellar.focusSearch")
}

/// The app's composition root: the state every window shares, made once and handed to each window
/// as it is built (docs/APP-ARCHITECTURE.md). Settings, Accounts and the welcome tour are separate
/// `NSWindow`s — a sheet under `NSHostingView` is a fatal AttributeGraph cycle — so they share no
/// view tree, and this is how they still see the same Cellar.
@MainActor
final class AppModel {
    /// The player's actions — one at a time, for the whole app.
    let activity = ActivityStore()
    /// The games, the selection and the sidebar's filters.
    let library = LibraryStore()
    /// Where the player is signed in.
    lazy var accounts = AccountsStore(activity: activity)
    /// The shared runtime downloading in the background — on its own runner, so it never holds Play.
    let preparation = RuntimePreparation()
    /// Sparkle, started the first time the menu bar asks for it.
    lazy var updater = AppUpdater()

    /// View › Add Installed Games Without a Profile: write draft profiles for them (`DraftProfile`),
    /// then show what turned up.
    func draftProfiles() {
        guard !activity.busy else { return }
        activity.run(.draftProfiles, title: "Finding games without a profile",
                     then: { [library] in library.refresh() })
    }
}

// A SwiftPM executable can't use @main App scenes, so stand the app up by hand: an NSApplication
// whose window hosts the SwiftUI ContentView. This is the Phase-3 "Steam-like" front-end over
// CellarKit — choose a game, see its state, and play it, with the game's own icon.
//
// Because there is no App scene, AppKit installs no default menu bar — so we build one ourselves
// (⌘Q to quit, About, Settings…, and the Edit menu that text fields need for cut/copy/paste).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var window: NSWindow!
    var settingsWindow: NSWindow?
    var accountsWindow: NSWindow?
    var folderAccessWindow: NSWindow?
    var welcomeTourWindow: NSWindow?

    /// The Dock icon's menu: the last few games played, newest first. Reads the playtime record
    /// only — no store is asked anything from a right-click.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let recent = Playtime.all()
            .compactMap { slug, record in record.lastPlayed.map { (slug, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .compactMap { slug, _ in (try? Game.plan(slug: slug)).map { (slug, $0.name) } }
        guard !recent.isEmpty else { return nil }
        let menu = NSMenu()
        let header = menu.addItem(withTitle: "Recently Played", action: nil, keyEquivalent: "")
        header.isEnabled = false
        for (slug, name) in recent {
            let item = menu.addItem(withTitle: name, action: #selector(showRecentGame(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = slug
        }
        return menu
    }

    @objc private func showRecentGame(_ sender: NSMenuItem) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.bringToFront()
        if let slug = sender.representedObject as? String { model.library.show(slug) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First thing, before anything can crash: this is also where a previous session that
        // never reached applicationWillTerminate gets noticed and written down.
        Diagnostics.processDidStart(version: Bundle.main.shortVersion)
        NSApp.mainMenu = buildMainMenu()

        // Started from inside the disk image: offer to move into Applications first. When the
        // player accepts, the moved copy opens and this one quits — so nothing else is set up here.
        if MoveToApplications.offerIfNeeded() { return }

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
            // A full-size content view under a transparent title bar: the sidebar's material runs
            // up behind the traffic lights, the way Music, Notes and the App Store look. SwiftUI
            // still lays content out below the title bar (it is a safe-area inset); only the
            // backgrounds reach into it.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Cellar"
        // The sidebar already carries the name and the mark; a second "Cellar" centred above the
        // game's banner is noise. The title stays set for the Window menu and Mission Control.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // A library is one window. Without this macOS adds "Show Tab Bar" and friends to the menus,
        // offering tabs of a window that has nothing to put in a second one.
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        // AppKit enforces the floor itself, rather than letting SwiftUI clip a window the player
        // dragged smaller than the layout can take.
        window.contentMinSize = NSSize(width: 880, height: 580)
        window.center()
        // Reopen where the player left it — size and position — as every document-less Mac app does.
        window.setFrameAutosaveName("CellarLibraryWindow")
        let useDiagnostic = ProcessInfo.processInfo.environment["CELLAR_DIAG"] != nil
        window.contentView = useDiagnostic
            ? NSHostingView(rootView: AnyView(Text("Cellar GUI works").padding()))
            : NSHostingView(rootView: ContentView(lib: model.library, runner: model.activity, preparation: model.preparation))
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.bringToFront()

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

        // The parts every game shares start downloading now, behind the tour, so the first
        // Install press is a game download and nothing else. A no-op once they are here.
        if !useDiagnostic {
            DispatchQueue.main.async { [model] in model.preparation.startIfNeeded() }
        }
    }

    @MainActor @objc private func uninstallCellar() { CellarUninstaller.begin(preparation: model.preparation) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Clears the marker `processDidStart` looks for. Quitting cleanly is how the next start knows
    /// the last one didn't.
    func applicationWillTerminate(_ notification: Notification) {
        Diagnostics.processWillExit()
    }

    // MARK: - Menu

    /// The menu bar, built to the Human Interface Guidelines' standard order — App, File, Edit,
    /// View, Window, Help — because a hand-rolled app gets none of it for free, and a missing menu
    /// is a missing keyboard path (skills/ux.md › Accessibility). Menu items are title case, as
    /// macOS's own are; everything inside the window stays sentence case.
    private func buildMainMenu() -> NSMenu {
        let appName = "Cellar"
        let mainMenu = NSMenu()

        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem()
            mainMenu.addItem(item)
            let menu = NSMenu(title: title)
            item.submenu = menu
            return menu
        }

        // App menu (its bold title comes from CFBundleName once wrapped as Cellar.app).
        let appMenu = submenu(appName)
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(showAbout), keyEquivalent: "")
            .target = self
        // Left out of a build from source: it has no feed to check, and a disabled item would only
        // raise a question it cannot answer. Settings › Updates says why.
        if let updates = model.updater.makeMenuItem() { appMenu.addItem(updates) }
        appMenu.addItem(withTitle: "Welcome to \(appName)…", action: #selector(showWelcomeTour), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            .target = self
        // ⌘⇧A: an upper-case key equivalent is the shifted one.
        appMenu.addItem(withTitle: "Accounts…", action: #selector(showAccounts), keyEquivalent: "A")
            .target = self
        appMenu.addItem(.separator())
        let services = appMenu.addItem(withTitle: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        // Next to Quit, where a Mac app that removes itself puts it; it asks before doing anything.
        appMenu.addItem(withTitle: "Uninstall \(appName)…", action: #selector(uninstallCellar), keyEquivalent: "")
            .target = self
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu — Close belongs here, not in Window, on every Mac.
        let fileMenu = submenu("File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        // Edit menu — text fields (the library search box) need these for cut/copy/paste/select-all.
        let editMenu = submenu("Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Find…", action: #selector(focusSearch), keyEquivalent: "f")
            .target = self

        // View menu.
        let viewMenu = submenu("View")
        viewMenu.addItem(withTitle: "Refresh Library", action: #selector(refreshLibrary), keyEquivalent: "r")
            .target = self
        viewMenu.addItem(withTitle: "Add Installed Games Without a Profile", action: #selector(draftProfiles), keyEquivalent: "")
            .target = self
        viewMenu.addItem(.separator())
        let fullScreen = viewMenu.addItem(withTitle: "Enter Full Screen",
                                          action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]

        // Window menu.
        let windowMenu = submenu("Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        // Help menu. Registering it is what gives macOS's menu search field, for free.
        let helpMenu = submenu("Help")
        helpMenu.addItem(withTitle: "\(appName) Help", action: #selector(openHelp), keyEquivalent: "?")
            .target = self
        helpMenu.addItem(withTitle: "Supported Games", action: #selector(openSupportedGames), keyEquivalent: "")
            .target = self
        helpMenu.addItem(.separator())
        helpMenu.addItem(withTitle: "Show Logs in Finder", action: #selector(showLogs), keyEquivalent: "")
            .target = self
        helpMenu.addItem(withTitle: "Report an Issue…", action: #selector(reportIssue), keyEquivalent: "")
            .target = self
        NSApp.helpMenu = helpMenu

        return mainMenu
    }

    @objc private func refreshLibrary() {
        model.library.refresh()
    }

    @objc private func draftProfiles() {
        model.draftProfiles()
    }

    @objc private func focusSearch() {
        window?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .cellarFocusSearch, object: nil)
    }

    @objc private func openHelp() { NSWorkspace.shared.open(Links.help) }
    @objc private func openSupportedGames() { NSWorkspace.shared.open(Links.supportedGames) }
    @objc private func showLogs() { NSWorkspace.shared.open(Paths.logs) }
    @objc private func reportIssue() { NSWorkspace.shared.open(Links.newIssue) }

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
            w.contentView = NSHostingView(rootView: SettingsView(runner: model.activity, library: model.library, accounts: model.accounts,
                                                                updater: model.updater, preparation: model.preparation, onClose: { [weak self] in
                self?.settingsWindow?.close()
            }))
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.bringToFront()
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
        NSApp.bringToFront()
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
            w.contentView = NSHostingView(rootView: WelcomeTourView(runner: model.activity, library: model.library, accounts: model.accounts,
                                                                   preparation: model.preparation, onFinish: { [weak self] in
                WelcomeTour.markSeen()
                self?.welcomeTourWindow?.close()
            }))
            welcomeTourWindow = w
        }
        WelcomeTour.markSeen()
        welcomeTourWindow?.makeKeyAndOrderFront(nil)
        NSApp.bringToFront()
    }

    @objc private func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Cellar",
            .applicationVersion: version,
            .credits: Self.aboutCredits(),
        ])
        NSApp.bringToFront()
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

/// Where the app sends a player for help. One table, so Settings and the Help menu never point at
/// two different pages.
enum Links {
    static let help = URL(string: "https://echarnus.github.io/Cellar/faq.html")!
    static let controllersHelp = URL(string: "https://echarnus.github.io/Cellar/faq.html#controllers")!
    static let supportedGames = URL(string: "https://echarnus.github.io/Cellar/")!
    static let repository = URL(string: "https://github.com/Echarnus/Cellar")!
    static let releases = URL(string: "https://github.com/Echarnus/Cellar/releases")!
    static let newIssue = URL(string: "https://github.com/Echarnus/Cellar/issues/new")!
}

extension Bundle {
    /// The version shown in About and written into the log; falls back to the library's own
    /// version when the app runs unwrapped during development.
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? CellarVersion.current
    }
}

extension NSApplication {
    /// Brings Cellar forward. Activation is cooperative from macOS 14, so the plain `activate()` is
    /// the call — `activate(ignoringOtherApps:)` is deprecated and its flag ignored.
    func bringToFront() {
        activate()
    }
}
