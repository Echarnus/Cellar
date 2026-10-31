import CellarDomain
import SwiftUI
import AppKit
import CellarKit
import CellarUI

/// Settings — and, first of all, **the** sign-in.
///
/// Accounts used to be a window of their own, reached from a menu item most people never opened,
/// while the library asked for a sign-in per game. Signing in is the first thing Cellar needs and
/// the thing a player goes looking for later, so it is the first section of the one window called
/// Settings. There is no second place to sign in.
struct SettingsView: View {
    /// The app's one activity (`AppModel`), so a command started here holds the library's buttons
    /// too, and the activity pane shows everything Cellar is running.
    let runner: ActivityStore
    /// The app's one library, told directly when an account changes.
    let library: LibraryStore
    let accounts: AccountsStore
    @Bindable var updater: AppUpdater
    let preparation: RuntimePreparation
    @AppStorage("showHUD") private var showHUD = false
    /// Settings is shown in a standalone NSWindow (not a SwiftUI sheet — that crashes under
    /// NSHostingView), so anything that hands off to another window closes this one through this
    /// callback rather than `dismiss`.
    var onClose: () -> Void = {}

    /// Where the diagnostics export has got to. Every one of these states is drawn: a button that
    /// silently writes a file somewhere is a button the player can't trust.
    private enum Export: Equatable {
        case idle, working
        case written(URL)
        case failed(String)
    }
    @State private var export: Export = .idle
    /// Read after the first layout, never from the body (skills/swift.md).
    @State private var databaseVersion = ""
    /// Measured off the main thread when the pane opens: walking a 100 GB game takes seconds.
    @State private var storageUsage: [GameStorage.Usage] = []

    private var runnerName: String { RunnerManager.installed().first?.spec.displayName ?? "not installed" }
    private var depot: String { DepotTool.isInstalled ? "installed" : "installs on first download" }

    /// Every state of the background download, said plainly — including "off".
    private var preparationNote: String {
        switch preparation.state {
        case .working(let line): return "Downloading now: \(line)"
        case .ready:             return "Everything every game shares is on this Mac."
        case .incomplete:        return "Stopped before it finished. Whatever is missing downloads when a game first needs it, or when Cellar next opens."
        case .idle:
            return preparation.isEnabled
                ? "The Windows runtime and Steam client download when Cellar opens, so a first game doesn't wait for them."
                : "Off: the Windows runtime and Steam client download when you set up your first game."
        }
    }

    /// The panes, in the order a player needs them: the sign-in first, then what changes how games
    /// run, then the machinery, then who made it.
    private enum Pane: String, CaseIterable {
        case accounts = "Accounts", general = "General", advanced = "Advanced", about = "About"
    }
    @State private var pane: Pane = .accounts

    var body: some View {
        VStack(spacing: 0) {
            // Tabs, as every Mac app's Settings has them, rather than one long scrolling form that
            // put the credits above the fold and the diagnostics below it. No "Done" button and no
            // in-window heading: settings apply as you change them, the title bar already says
            // "Settings", and the window closes like any other (⌘W or the red button).
            TabView(selection: $pane) {
                Form {
                    // Signing in is account-level, so it belongs here as well as behind ⌘⇧A — the
                    // welcome tour promises "you can do this later in Settings", and this is that.
                    Section {
                        AccountsSection(runner: runner, library: library, state: accounts.state, refresh: { accounts.refresh() })
                            .padding(.vertical, 4)
                    } footer: {
                        Text("One sign-in per store covers your whole library.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .tabItem { Label(Pane.accounts.rawValue, systemImage: "person.crop.circle") }
                .tag(Pane.accounts)

                Form {
                    Section("Gameplay") {
                        Toggle("Show Metal performance overlay (FPS)", isOn: $showHUD)
                        Text("Shows FPS and frame time in every game you launch.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    GameLanguageSection()
                    WheelStrengthSection()
                    Section("Folder access") {
                        Button("Review folder access…") {
                            onClose()
                            NotificationCenter.default.post(name: .cellarOpenFolderAccess, object: nil)
                        }
                        Text("Which of your Documents, Desktop and Downloads folders Windows games may use. A folder that is off isn't a failure — those games keep their saves inside their bottle instead.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Help") {
                        Button("Show the welcome tour again") {
                            NotificationCenter.default.post(name: .cellarOpenWelcomeTour, object: nil)
                        }
                        Link("Questions & answers", destination: Links.help)
                    }
                }
                .formStyle(.grouped)
                .tabItem { Label(Pane.general.rawValue, systemImage: "gearshape") }
                .tag(Pane.general)

                Form {
                    Section("Runtime") {
                        LabeledContent("Wine runner", value: runnerName)
                        LabeledContent("DepotDownloader", value: depot)
                        Toggle("Download what every game needs ahead of time", isOn: Binding(
                            get: { preparation.isEnabled },
                            set: { preparation.isEnabled = $0 }))
                        Text(preparationNote)
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Open Cellar folder") { NSWorkspace.shared.open(Paths.appSupport) }
                    }
                    gameDatabase
                    storage
                    diagnostics
                    Section("Uninstall") {
                        Button("Uninstall Cellar…") {
                            onClose()
                            CellarUninstaller.begin(preparation: preparation)
                        }
                        Text("Removes Cellar and everything it downloaded. You choose whether to keep your save games first.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .tabItem { Label(Pane.advanced.rawValue, systemImage: "wrench.and.screwdriver") }
                .tag(Pane.advanced)

                Form {
                    Section("About") {
                        LabeledContent("Version", value: appVersion)
                        Link("Cellar on GitHub", destination: Links.repository)
                        Link("Supported games", destination: Links.supportedGames)
                        Text(Credits.nonAffiliation)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    updates
                    // Wine gets its own group rather than a line among the links: Cellar is a
                    // launcher over it, and a player reading "About" should leave knowing that.
                    Section("Built on Wine") {
                        Text(Credits.wine.role)
                            .font(.caption).foregroundStyle(.secondary)
                        Link("Wine — winehq.org", destination: Credits.wine.url)
                        Link("Wine source — gitlab.winehq.org", destination: Credits.wine.sourceURL!)
                        LabeledContent("License", value: Credits.wine.license)
                    }
                    Section("With thanks to") {
                        ForEach(Credits.all.dropFirst(), id: \.name) { credit in
                            VStack(alignment: .leading, spacing: 2) {
                                Link(credit.name, destination: credit.url)
                                Text(credit.role).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .tabItem { Label(Pane.about.rawValue, systemImage: "info.circle") }
                .tag(Pane.about)
            }
            .padding(.top, 8)
            Divider()
            activity
        }
        // A *fixed* size, and the window is not resizable. A flexible root frame inside
        // NSHostingView lets layout feed back into the view graph, and this app aborts in
        // AttributeGraph when that happens (skills/swift.md). Not worth being clever about.
        .frame(width: 560, height: 680)
        .onAppear { accounts.refresh() }
    }

    /// Always present, at a fixed height, rather than appearing when something happens: a pane that
    /// materialises mid-run changes the view tree's shape during layout, which is what this app
    /// crashes on. Empty, it explains itself.
    private var activity: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if runner.busy {
                    ProgressView().controlSize(.small)
                    Text(runner.busyTitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.top, 8)
            ScrollView {
                Text(runner.log.isEmpty ? "Anything Cellar runs shows up here." : runner.log)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(runner.log.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 92)
        }
        .background(Color.primary.opacity(0.04))
    }

    // MARK: - Updates

    /// Every word here is true of this build: a release says when it last looked, a build from
    /// source says it does not look at all rather than showing a switch that does nothing.
    @ViewBuilder private var updates: some View {
        Section("Updates") {
            if updater.isAvailable {
                Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                HStack {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                    Spacer()
                    Text(lastChecked).font(.caption).foregroundStyle(.secondary)
                }
                Text("""
                    Cellar looks for a new version once a day and shows you what changed. \
                    Nothing is installed until you choose Install, and your games and bottles stay as they are.
                    """)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("""
                    This copy of Cellar was built from source, so it doesn't update itself. \
                    Pull the latest code and run Scripts/install-app.sh, or install a release from GitHub.
                    """)
                    .font(.caption).foregroundStyle(.secondary)
                Link("Cellar releases", destination: Links.releases)
            }
        }
    }

    private var lastChecked: String {
        guard let date = updater.lastChecked else { return "Not checked yet" }
        return "Last checked " + date.formatted(.relative(presentation: .named))
    }

    // MARK: - Game database

    /// Which set of game profiles is in use, and a way to fetch the newest — said honestly for a
    /// build that has no key to check a download with.
    @ViewBuilder private var gameDatabase: some View {
        Section("Game database") {
            LabeledContent("In use", value: databaseVersion)
            if ProfileUpdates.publicKey.isEmpty {
                Text("This copy of Cellar can't check a downloaded game database, so it uses the one it shipped with. Installing a newer Cellar brings newer games.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Check for new games now") {
                    runner.run(.updateProfiles(quiet: false), title: "Updating the game database",
                               then: { databaseVersion = Self.describeDatabase() })
                }
                .disabled(runner.busy)
                Text("New and fixed game profiles are published with every Cellar release, signed. Cellar checks once a day and keeps the ones it has if anything doesn't check out. Profiles you add yourself always win.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { databaseVersion = Self.describeDatabase() }
    }

    static func describeDatabase() -> String {
        guard let installed = ProfileUpdates.installed else { return "The one Cellar \(CellarVersion.current) shipped with" }
        return "\(installed.count) profiles from Cellar \(installed.cellarVersion), fetched "
            + installed.fetched.formatted(.relative(presentation: .named))
    }

    // MARK: - Storage

    /// What Cellar takes on disk, measured when the pane opens, with the one safe clean-up.
    @ViewBuilder private var storage: some View {
        Section("Storage") {
            if storageUsage.isEmpty {
                Text("Measuring…").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(storageUsage.prefix(8), id: \.label) { item in
                    LabeledContent(item.label, value: ByteSize.describe(item.bytes))
                }
            }
            Button("Clean Up Installers and Scratch Files") {
                runner.run(.cleanStorage, title: "Cleaning up", then: { measureStorage() })
            }
            .disabled(runner.busy)
            Text("Removes downloaded installers and temporary files Cellar fetches again when it needs them. Games, bottles, save games and sign-ins stay. To move a game to an external drive, use the ••• menu on its page.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { measureStorage() }
    }

    private func measureStorage() {
        Task.detached(priority: .utility) {
            let usage = GameStorage.usage()
            await MainActor.run { storageUsage = usage }
        }
    }

    // MARK: - Diagnostics

    /// Cellar keeps a rolling record of set-ups, launches and failures. This is where a player
    /// turns that into one file they can attach to a bug report — the whole reason it is kept.
    @ViewBuilder private var diagnostics: some View {
        Section("Diagnostics") {
            LabeledContent("Kept log", value: logSize)
            HStack {
                Button("Export diagnostics…") { exportReport() }
                    .disabled(export == .working)
                Button("Open logs folder") { NSWorkspace.shared.open(Paths.logs) }
            }
            Text("""
                Writes one text file — your Mac's details, Cellar's log of what it did, and the \
                tail of each Wine log — to your Desktop. Account names, your home folder path \
                and anything token-shaped are left out.
                """)
                .font(.caption).foregroundStyle(.secondary)

            switch export {
            case .idle:
                EmptyView()
            case .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Collecting…").font(.caption).foregroundStyle(.secondary)
                }
            case .written(let url):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Saved \(url.lastPathComponent) to your Desktop.").font(.caption)
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }.controlSize(.small)
                }
            case .failed(let reason):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        .accessibilityLabel("Export failed")
                    Text(reason).font(.caption).textSelection(.enabled)
                }
            }
        }
    }

    private var logSize: String {
        let bytes = CellarLog.historySize
        if bytes == 0 { return "nothing logged yet" }
        return bytes < 1024 ? "\(bytes) bytes" : "\(bytes / 1024) KB"
    }

    /// Off the main thread: the report shells out to `sysctl`, `arch` and `gh`, and a Settings
    /// window that beachballs while doing it would be its own bug.
    private func exportReport() {
        export = .working
        let version = appVersion
        Task.detached {
            do {
                let url = try Diagnostics.exportReport(cellarVersion: version)
                await MainActor.run { export = .written(url) }
            } catch {
                await MainActor.run { export = .failed(CellarLog.describe(error)) }
            }
        }
    }

    private var appVersion: String { Bundle.main.shortVersion }
}
