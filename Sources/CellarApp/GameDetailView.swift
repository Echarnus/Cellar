import SwiftUI
import AppKit
import GameController
import CellarKit
import CellarUI

struct GameDetailView: View {
    let game: GameSummary
    @ObservedObject var runner: CellarRunner
    let onChange: () -> Void
    @AppStorage("showHUD") private var showHUD = false
    @State private var showDetails = false
    /// True while a removal is being measured. Walking a 36 GB Steam library takes a few seconds,
    /// and a menu item that appears to do nothing for that long reads as broken.
    @State private var measuringRemoval = false
    /// The game's language submenu, read when the page appears rather than from the body.
    @State private var language = GameLanguageMenu.Selection()
    /// The newest copy of this game's saves, read when the page appears and after a backup or restore.
    @State private var latestBackup: SaveBackups.Backup?
    /// The controllers macOS sees, kept current as pads come and go.
    @State private var pads: [Controllers.Pad] = []
    /// Wheels, pedals and shifters, read when the page appears (macOS posts no notice for them).
    @State private var wheels: [Wheels.Device] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 18) {
                    actions
                    Text(game.actionHint)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let drive = game.missingDrive {
                        Label("\(game.name) is on the drive “\(drive)”, which isn't connected. Connect it to play.",
                              systemImage: "externaldrive.badge.xmark")
                            .font(.callout).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    notice
                    chips
                    information
                    if game.bottleExists { saves }
                    activityLog
                }
                .padding(24)
            }
        }
        .background(.background)
        .task(id: game.slug) {
            language = .load(game)
            latestBackup = SaveBackups.list(bottle: game.bottleName).first
            pads = Controllers.connected()
            wheels = Wheels.connected()
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in pads = Controllers.connected() }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in pads = Controllers.connected() }
    }

    // MARK: - Hero

    /// Banner, cover, title — and the store, spelled out directly under the name. Which storefront
    /// a game belongs to is the first thing that changes what every control below does, so it is
    /// given a line of its own rather than hidden in a details table.
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            GameBanner(game: game)
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 16) {
                GameCover(game: game, width: 92, showsBadge: false)
                VStack(alignment: .leading, spacing: 7) {
                    Text(game.name)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(.white).shadow(radius: 4).lineLimit(2)
                    HStack(spacing: 8) {
                        StoreLockup(store: game.store)
                        if let account = game.account {
                            Text("Signed in as \(account)")
                                .font(.caption).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                Spacer()
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipped()
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button { primary() } label: {
                HStack(spacing: 8) {
                    Image(systemName: game.actionSymbol).font(.title3)
                    Text(game.actionTitle).fontWeight(.semibold)
                }
                .frame(minWidth: 168).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            // Green means "go" for Play; every other step is tinted by the store whose client is
            // about to appear, so the button and the window that opens belong to each other.
            .tint(game.nextStep == .play ? .green : game.store.tint)
            .disabled(runner.busy || measuringRemoval)
            .keyboardShortcut(.defaultAction)
            .help(game.actionHint)

            status
            Spacer()
            overflowMenu
        }
    }

    /// What Cellar is doing right now, beside the button that started it.
    ///
    /// A launch is not like the other commands: `cellar launch` stays alive for the whole session so
    /// it can close the layer afterwards, so a plain "busy" spinner would sit there saying
    /// "Launching" for the length of the game. Playing is its own state, and it gets said.
    @ViewBuilder private var status: some View {
        if runner.phase == .playing, runner.launchingSlug == game.slug {
            Label("Playing", systemImage: "play.circle.fill")
                .font(.callout.weight(.medium)).foregroundStyle(.green)
                .help("\(game.name) is running. Quit the game and Cellar closes the layer.")
        } else if runner.busy, runner.installingSlug == game.slug {
            InstallProgressBar(game: game.name, store: game.store, progress: runner.installProgress)
        } else if runner.busy {
            ProgressView().controlSize(.small)
            Text(runner.busyTitle).font(.callout).foregroundStyle(.secondary)
            if runner.launchingSlug == game.slug {
                Button("Show progress") { LaunchSplashWindow.present(game: game, runner: runner) }
                    .buttonStyle(.link)
                    .help("Bring the launch window back.")
            }
        } else if measuringRemoval {
            // Measuring runs before the uninstall sheet appears, and it touches the disk, so the
            // gap has to be accounted for rather than looking like a dead button.
            ProgressView().controlSize(.small)
            Text("Working out what would be deleted…")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button("Set up bottle") { act(["setup", "--profile", game.slug], "Setting up") }
            Divider()
            switch game.store {
            case .steam:
                // A game with no live-session DRM gets no Steam client in its bottle, so the
                // client's own actions are only offered where there is (or will be) one.
                let hasClient = game.needsLiveSession || game.clientInstalled
                if hasClient {
                    Button("Open Steam") { act(["steam", "open", game.slug], "Opening Steam") }
                }
                Button("Download game") { act(["install", game.slug], "Downloading \(game.name)") }
                if hasClient {
                    Button("Install through the Steam client") { act(["steam", "install", game.slug], "Installing") }
                }
                Button("Add to Steam library") { act(["steam", "add", game.slug], "Adding") }
            case .battlenet:
                Button("Open Battle.net") { act(["battlenet", "open", game.slug], "Opening Battle.net") }
                Button("Re-apply Battle.net settings") { act(["battlenet", "configure", game.slug], "Configuring") }
            case .gog:
                Button("Download and install from GOG") { act(["gog", "install", game.slug], "Installing") }
                Button("GOG accounts…") { NotificationCenter.default.post(name: .cellarOpenAccounts, object: nil) }
            }
            // Any game whose files Cellar fetched from a Steam depot — with or without a live session.
            if game.update != nil {
                if game.updatePending {
                    Button("Update now") { runner.update(slug: game.slug, name: game.name) { onChange() } }
                }
                Button("Check for updates") {
                    act(["update", game.slug, "--check"], "Checking \(game.name) for updates")
                }
            }
            // The game's own app — its name, its icon — whatever store it came from. A wrapper for
            // the store client is not offered on a game's page: there it read as the game's app.
            Button("Add \(game.name) to Applications") { act(["app", game.slug], "Adding to Applications") }
            // The game's own language needs its bottle to live in; before set-up there is none.
            if game.bottleExists {
                GameLanguageMenu(game: game, state: $language)
            }
            Divider()
            if game.isDraft {
                // A guess that works is worth handing in: the file is an ordinary profile.
                Button("Save Profile As…") { exportProfile() }
            }
            if game.isOnOtherDrive {
                Button("Move Back to This Mac") { act(["storage", "move-back", game.slug], "Moving \(game.name) back") }
                    .disabled(game.missingDrive != nil)
            } else if game.gameInstalled, game.store != .battlenet {
                Button("Move to Another Drive…") { chooseDrive() }
            }
            Button("Show logs in Finder") { NSWorkspace.shared.open(Paths.logs) }
            // Removal is last and on its own, where destructive actions belong. Each entry states
            // what it takes, and neither does anything until the confirmation has been read.
            if game.gameInstalled || game.bottleExists {
                Divider()
                if game.gameInstalled {
                    Button("Uninstall \(game.name)…", role: .destructive) { confirmRemoval(scope: .game) }
                }
                if game.bottleExists {
                    Button("Remove the bottle '\(game.bottleName)'…", role: .destructive) { confirmRemoval(scope: .bottle) }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("More actions for \(game.name)")
        .accessibilityLabel("More actions")
    }

    // MARK: - Notices

    /// A heads-up shown only where a store is about to behave in a way the player would otherwise
    /// read as a bug. Setting the expectation costs one line; a mystery window costs a support thread.
    @ViewBuilder private var notice: some View {
        if game.setupPending && game.nextStep != .play && !game.store.descriptor.hasSilentInstaller {
            Notice(symbol: "hand.raised.fill", tint: game.store.tint,
                   title: "\(game.store.displayName)'s installer needs a few clicks",
                   detail: "Blizzard ships no silent installer. Partway through setup its window opens — click through it and leave the app running. Cellar picks up from there.")
        } else if game.nextStep == .install && game.store == .gog {
            Notice(symbol: "clock.fill", tint: game.store.tint,
                   title: "The install runs with no window",
                   detail: "GOG ships a normal Windows installer and Cellar runs it silently, so there is nothing to watch for a few minutes. The activity log below is the progress.")
        } else if game.nextStep == .play && game.clientSignInPending {
            // Cellar normally hands the client the player's session, so this only shows when it
            // can't — and a second sign-in needs its reason on the page, or it reads as Cellar
            // forgetting the first one.
            Notice(symbol: "person.crop.circle.badge.questionmark", tint: game.store.tint,
                   title: "\(game.store.displayName) asks you to sign in once more",
                   detail: "\(game.name)'s DRM checks the \(game.store.displayName) app, which keeps a sign-in of its own. Cellar usually signs it in with your sign-in from Settings, but can't right now. The first time you press Play, its window opens — the QR code with the mobile app is quickest. Every \(game.store.displayName) game shares it.")
        } else if game.nextStep == .play && game.store == .battlenet {
            Notice(symbol: "bolt.horizontal.circle.fill", tint: game.store.tint,
                   title: "Battle.net stays open while you play",
                   detail: "Diablo's login and patching live in the client, so Cellar keeps it running in the background and closes the whole layer when you quit the game.")
        }
    }

    // MARK: - Chips

    private var chips: some View {
        HStack(spacing: 8) {
            Chip(game.statusText, system: game.statusSymbol, tint: game.statusTint)
            // Each store identifies a game its own way — an AppID, a product code, or neither.
            // Showing the right one is a small honesty that saves a support round-trip.
            switch game.store {
            case .gog:
                Chip("DRM-free", system: "lock.open.fill")
            case .steam:
                Chip(game.appID.map { "AppID \($0)" } ?? "No AppID", system: "number")
            case .battlenet:
                Chip(game.productCode.map { "Product " + $0 } ?? "No product code", system: "tag")
            }
            // From the profile, not from what is on disk: before the download, a game that never
            // talks to its store must not be labelled as needing it.
            let needsClient = game.needsClientAtRuntime && game.needsLiveSession
                && game.store.descriptor.installsClientInBottle
            Chip(needsClient ? "Needs \(game.store.displayName) running" : "Runs on its own",
                 system: needsClient ? "link" : "bolt.fill")
            if let update = game.update { updateChip(update) }
            Spacer()
        }
    }

    /// Whether this copy is Steam's current build. Only for a game Cellar downloaded: Steam keeps
    /// its own library current, and a chip claiming Cellar checked that would be a claim about
    /// nothing. "Up to date" is only ever said with the time Steam said it.
    @ViewBuilder private func updateChip(_ update: GameUpdates.State) -> some View {
        switch update {
        case .upToDate(let checked) where GameUpdates.isFresh(update, within: GameUpdates.recheckInterval):
            Chip("Up to date", system: "checkmark.seal")
                .help("Steam confirmed this is the current build \(Self.relative(checked)).")
        case .upToDate(let checked):
            // An old "up to date" is only a fact about the past; say when, not what.
            Chip("Checked \(Self.relative(checked))", system: "clock")
                .help("Steam said this was the current build then. Play checks again before it starts the game.")
        case .available(let checked):
            Chip("Update available", system: "arrow.down.circle.fill", tint: .blue)
                .help("Steam has a newer build than the one on disk (checked \(Self.relative(checked))). Play downloads only what changed, first.")
        case .unknown:
            Chip("Not checked for updates", system: "questionmark.circle")
                .help("Cellar hasn't been able to ask Steam yet. Play checks before it starts the game.")
        }
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Information

    /// What this game actually is, and what Cellar knows about running it.
    ///
    /// A Steam title has a store page one click away; a Battle.net one has nothing of the sort, so
    /// the profile is the only description the player gets. `notes` is the important one — it is
    /// where the profile records what has genuinely been tested and what has not, and hiding that
    /// would turn an honest "untested" into an implied promise.
    @ViewBuilder private var information: some View {
        let facts = game.facts
        VStack(alignment: .leading, spacing: 14) {
            if !facts.about.isEmpty || !facts.compatibility.isEmpty {
                // Two columns when the pane is wide enough for them, one when it isn't. At the
                // window's minimum width the side-by-side version wraps every value onto three
                // lines, which reads as broken rather than compact.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 32) {
                        factColumns(facts)
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 14) { factColumns(facts) }
                }
            }

            FactList(title: "Runtime", rows: [
                ("Runner", game.runnerID),
                ("Graphics", graphicsValue),
                ("Store", game.store.displayName),
                ("Bottle", game.bottleName),
            ])

            if game.backendIsPlayerChoice, let profiles = game.profileBackend.flatMap(GraphicsBackend.init(rawValue:)) {
                Button("Go back to \(profiles.displayName), the profile's backend") { resetBackend() }
                    .buttonStyle(.link).font(.callout)
                    .disabled(runner.busy)
                    .help("\(game.name) starts on \(profiles.displayName) again from its next launch. \(profiles.summary)")
            }

            controllerLine

            if let notes = facts.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("Notes").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            .kerning(0.5).textCase(.uppercase)
                        if let status = facts.status { StatusBadge(status: status) }
                    }
                    Text(notes).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 2)
    }

    /// The backend, and whose choice it is — a switch the player made is never shown as the profile's.
    private var graphicsValue: String {
        let name = GraphicsBackend(rawValue: game.backend)?.displayName ?? game.backend
        return game.backendIsPlayerChoice ? "\(name) — your choice" : name
    }

    private func resetBackend() {
        // A link has nowhere to show an error; a write that failed leaves the row as it was, which
        // is the truth.
        guard (try? BackendChoice.set(nil, in: BottleConfig.url(forBottle: game.bottleName))) != nil else { return }
        onChange()
    }

    /// The pads connected now, next to what the profile recorded about this game and a controller.
    /// Said as two facts, never combined into a promise that the pad will work in the game.
    @ViewBuilder private var controllerLine: some View {
        if !pads.isEmpty || !wheels.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                if !pads.isEmpty {
                    Label("Connected: " + pads.map(\.name).joined(separator: ", "), systemImage: "gamecontroller")
                        .font(.callout)
                }
                if !wheels.isEmpty {
                    Label("Connected: " + wheels.map(\.name).joined(separator: ", "), systemImage: "steeringwheel")
                        .font(.callout)
                    Text(Wheels.forceFeedbackNote)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if game.facts.controller == nil {
                    Text("This game's profile doesn't say how it handles a controller yet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let note = Controllers.steamInputNote(store: game.store, throughClient: game.needsClientAtRuntime) {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            if !wheels.isEmpty {
                // A wheel's set-up happens outside Cellar (PC mode, firmware), so say where to read it.
                Link("How to set up a racing wheel", destination: Links.controllersHelp)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder private func factColumns(_ facts: GameFacts) -> some View {
        if !facts.about.isEmpty { FactList(title: "About", rows: facts.about) }
        if !facts.compatibility.isEmpty { FactList(title: "Compatibility", rows: facts.compatibility) }
    }

    /// Saves live in the bottle; Cellar copies them out before anything that could lose them. This
    /// says when it last did, and offers the two things a player wants from that: another copy now,
    /// and the last one back.
    private var saves: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save games").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                .kerning(0.5).textCase(.uppercase)
            Text(backupSummary).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Back up now") {
                    runner.run(["saves", "backup", game.slug], title: "Backing up saves", then: { refreshBackups() })
                }
                Button("Restore last backup…") { confirmRestore() }
                    .disabled(latestBackup == nil)
                Button("Show in Finder") {
                    NSWorkspace.shared.open(SaveBackups.directory(forBottle: game.bottleName))
                }
                .disabled(latestBackup == nil)
            }
            .disabled(runner.busy)
        }
    }

    private var backupSummary: String {
        guard let backup = latestBackup else {
            return "No backup yet. Cellar takes one by itself before a reset, an update or removing the bottle."
        }
        let when = RelativeDateTimeFormatter().localizedString(for: backup.manifest.created, relativeTo: Date())
        return "Last backed up \(when) — \(backup.manifest.reason.description.lowercased()), \(ByteSize.describe(backup.manifest.bytes)). Cellar keeps the last \(SaveBackups.keep)."
    }

    private func refreshBackups() {
        latestBackup = SaveBackups.list(bottle: game.bottleName).first
    }

    /// A restore replaces the saves the game has now, so it is asked first — with the one fact that
    /// makes it safe to say yes: the current saves are kept too.
    private func confirmRestore() {
        guard let backup = latestBackup else { return }
        let alert = NSAlert()
        alert.messageText = "Restore \(game.name)'s saves from \(backup.id)?"
        alert.informativeText = "The saves the game has now are replaced by that backup (\(backup.manifest.reason.description.lowercased())). Cellar keeps a copy of the current ones first, so you can go back."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runner.run(["saves", "restore", game.slug, "--backup", backup.id], title: "Restoring saves", then: { refreshBackups() })
    }

    private var activityLog: some View {
        DisclosureGroup(isExpanded: $showDetails) {
            ScrollView {
                Text(runner.log.isEmpty ? "Nothing has run yet." : runner.log)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            .frame(height: 200)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        } label: {
            Label("Activity log", systemImage: "terminal").font(.callout)
        }
    }

    // MARK: - Behaviour

    private func primary() {
        switch game.nextStep {
        case .play:
            // The launch gets a window of its own: it is a minute or two of work with several
            // steps, and a spinner beside the button reads as a hang.
            let launched = game
            runner.launch(slug: game.slug, showHUD: showHUD) {
                onChange()
                // Played and quit: the one moment "how did it run?" has an answer.
                if runner.stage == .closed { CompatibilityPrompt.offerAfterSession(launched) }
            }
            LaunchSplashWindow.present(game: game, runner: runner, onFinished: { onChange() })
        case .setup:
            act(["setup", "--profile", game.slug], "Setting up")
        case .install:
            // One verb for every store. The route still differs — Cellar downloads a Steam or GOG
            // game itself and opens Blizzard's client for a Battle.net one — but that is a fact
            // about the store, not something the player should have to know to press a button.
            runner.install(slug: game.slug,
                           title: game.store == .battlenet ? "Opening Battle.net" : "Downloading \(game.name)",
                           then: { onChange() })
        }
    }

    /// Copy a draft profile out, for contributing it once the game is known to run.
    private func exportProfile() {
        guard let source = ProfileStore.find(game.slug)?.url else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = source.lastPathComponent
        panel.message = "Cellar guessed this profile's settings. If \(game.name) runs, set status and notes to what you saw, then contribute it to Cellar's profiles."
        guard panel.runModal() == .OK, let target = panel.url else { return }
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: source, to: target)
    }

    /// Pick a folder on another drive, then move the game there through the CLI.
    private func chooseDrive() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Move Here"
        panel.message = "Choose a folder on the drive to move \(game.name) to. Cellar puts it in a “Cellar Games” folder there, and the game plays and updates from it while the drive is connected."
        panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        act(["storage", "move", game.slug, "--to", folder.path], "Moving \(game.name)")
    }

    private func act(_ args: [String], _ title: String) {
        runner.run(args, title: title, then: { onChange() })
    }

    /// Show what removal would take, and only then run it — through the CLI, like every other
    /// side-effecting action, so the app inherits the same tested path (and its activity log).
    private func confirmRemoval(scope: RemovalScope) {
        measuringRemoval = true
        UninstallConfirmation.ask(for: game, scope: scope, measured: { measuringRemoval = false }) {
            act(["uninstall", game.slug, "--yes"] + (scope == .bottle ? ["--bottle"] : []),
                scope == .bottle ? "Removing the bottle" : "Uninstalling")
        }
    }
}

/// A short, calm heads-up. Not an alert: nothing here is wrong, it just isn't obvious.
struct Notice: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint).font(.callout)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(tint.opacity(0.22), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

struct Chip: View {
    let text: String
    let system: String
    var tint: Color = .secondary

    init(_ text: String, system: String, tint: Color = .secondary) {
        self.text = text
        self.system = system
        self.tint = tint
    }

    var body: some View {
        Label(text, systemImage: system).font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
    }
}

/// A titled label/value list. Values wrap; labels stay a fixed column so two lists line up.
struct FactList: View {
    let title: String
    let rows: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                .kerning(0.5).textCase(.uppercase)
            ForEach(rows, id: \.label) { row in
                HStack(alignment: .top, spacing: 10) {
                    Text(row.label).font(.callout).foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .leading)
                    Text(row.value).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: 380, alignment: .leading)
    }
}

/// How far a profile has actually been verified. Said plainly, because "untested" is information
/// the player needs *before* a two-hour download, not after it.
struct StatusBadge: View {
    let status: String

    private var tint: Color {
        switch status.lowercased() {
        case let s where s.hasPrefix("playable"): return .green
        case let s where s.hasPrefix("broken"), let s where s.hasPrefix("unplayable"): return .red
        default: return .orange
        }
    }

    var body: some View {
        Text(status.replacingOccurrences(of: "-", with: " "))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .accessibilityLabel("Compatibility status: \(status)")
    }
}
