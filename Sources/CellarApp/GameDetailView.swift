import SwiftUI
import AppKit
import CellarKit

struct GameDetailView: View {
    let game: GameSummary
    @ObservedObject var runner: CellarRunner
    let onChange: () -> Void
    @AppStorage("showHUD") private var showHUD = false
    @State private var showDetails = false
    /// True while a removal is being measured. Walking a 36 GB Steam library takes a few seconds,
    /// and a menu item that appears to do nothing for that long reads as broken.
    @State private var measuringRemoval = false

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
                    notice
                    chips
                    information
                    activityLog
                }
                .padding(24)
            }
        }
        .background(.background)
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
            .disabled(runner.busy || measuringRemoval || primaryIsManual)
            .keyboardShortcut(.defaultAction)
            .help(game.actionHint)

            if runner.busy {
                ProgressView().controlSize(.small)
                Text(runner.busyTitle).font(.callout).foregroundStyle(.secondary)
            } else if measuringRemoval {
                ProgressView().controlSize(.small)
                Text("Working out what would be deleted…")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            overflowMenu
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button("Set up bottle") { act(["setup", "--profile", game.slug], "Setting up") }
            Divider()
            switch game.store {
            case .steam:
                Button("Open Steam") { act(["steam", "open", game.slug], "Opening Steam") }
                Button("Install game") { act(["steam", "install", game.slug], "Installing") }
                Button("Add to Steam library") { act(["steam", "add", game.slug], "Adding") }
                Button("Create Steam app in ~/Applications") { act(["steam", "app", game.slug], "Creating app") }
            case .battlenet:
                Button("Open Battle.net") { act(["battlenet", "open", game.slug], "Opening Battle.net") }
                Button("Re-apply Battle.net settings") { act(["battlenet", "configure", game.slug], "Configuring") }
                Button("Create Battle.net app in ~/Applications") { act(["battlenet", "app", game.slug], "Creating app") }
            case .gog:
                Button("Download and install from GOG") { act(["gog", "install", game.slug], "Installing") }
                Button("GOG accounts…") { NotificationCenter.default.post(name: .cellarOpenAccounts, object: nil) }
            case .standalone:
                Button("Copy download command") { copyDownloadCommand() }
            }
            Divider()
            Button("Show logs in Finder") { NSWorkspace.shared.open(Paths.logs) }
            // Removal is last and on its own, where destructive actions belong. Each entry states
            // what it takes, and neither does anything until the confirmation has been read.
            if game.gameInstalled || game.bottleExists {
                Divider()
                if game.gameInstalled {
                    Button("Uninstall \(game.name)…") { confirmRemoval(scope: .game) }
                }
                if game.bottleExists {
                    Button("Remove the bottle '\(game.bottleName)'…") { confirmRemoval(scope: .bottle) }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityLabel("More actions")
    }

    // MARK: - Notices

    /// A heads-up shown only where a store is about to behave in a way the player would otherwise
    /// read as a bug. Setting the expectation costs one line; a mystery window costs a support thread.
    @ViewBuilder private var notice: some View {
        if game.nextStep == .setup && !game.store.descriptor.hasSilentInstaller {
            Notice(symbol: "hand.raised.fill", tint: game.store.tint,
                   title: "\(game.store.displayName)'s installer needs a few clicks",
                   detail: "Blizzard ships no silent installer. Partway through setup its window opens — click through it and leave the app running. Cellar picks up from there.")
        } else if game.nextStep == .install && game.store == .standalone {
            Notice(symbol: "terminal.fill", tint: .secondary,
                   title: "This download runs in Terminal",
                   detail: "Steam Guard prompts for a code, which needs a real terminal. Copy the command from the ••• menu and run it, then come back.")
        } else if game.nextStep == .install && game.store == .gog {
            Notice(symbol: "clock.fill", tint: game.store.tint,
                   title: "The install runs with no window",
                   detail: "GOG ships a normal Windows installer and Cellar runs it silently, so there is nothing to watch for a few minutes. The activity log below is the progress.")
        } else if game.nextStep == .play && game.store == .battlenet {
            Notice(symbol: "bolt.horizontal.circle.fill", tint: game.store.tint,
                   title: "Battle.net stays open while you play",
                   detail: "Diablo's login and patching live in the client, so Cellar keeps it running in the background and closes the whole layer when you quit the game.")
        }
    }

    // MARK: - Chips

    private var chips: some View {
        HStack(spacing: 8) {
            Chip(game.nextStep == .play ? "Ready to play" : "Setup required",
                 system: game.nextStep == .play ? "checkmark.circle.fill" : "wrench.and.screwdriver",
                 tint: game.nextStep == .play ? .green : .orange)
            // Each store identifies a game its own way — an AppID, a product code, or neither.
            // Showing the right one is a small honesty that saves a support round-trip.
            switch game.store {
            case .gog:
                Chip("DRM-free", system: "lock.open.fill")
            case .steam:
                Chip(game.appID.map { "AppID \($0)" } ?? "No AppID", system: "number")
            case .battlenet:
                Chip(game.productCode.map { "Product " + $0 } ?? "No product code", system: "tag")
            case .standalone:
                Chip("No store", system: "shippingbox")
            }
            Chip(game.needsClientAtRuntime ? "Needs \(game.store.displayName) running" : "Runs on its own",
                 system: game.needsClientAtRuntime ? "link" : "bolt.fill")
            Spacer()
        }
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
                ("Graphics", game.backend.uppercased()),
                ("Store", game.store.displayName),
                ("Bottle", game.bottleName),
            ])

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

    @ViewBuilder private func factColumns(_ facts: GameFacts) -> some View {
        if !facts.about.isEmpty { FactList(title: "About", rows: facts.about) }
        if !facts.compatibility.isEmpty { FactList(title: "Compatibility", rows: facts.compatibility) }
    }

    private var activityLog: some View {
        DisclosureGroup(isExpanded: $showDetails) {
            ScrollView {
                Text(runner.log.isEmpty ? "Ready." : runner.log)
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

    /// True when the next step is something Cellar cannot do for the player from a button.
    private var primaryIsManual: Bool {
        game.nextStep == .install && game.store == .standalone
    }

    private func primary() {
        switch game.nextStep {
        case .play:
            act(["launch", game.slug] + (showHUD ? ["--hud"] : []), "Launching")
        case .setup:
            act(["setup", "--profile", game.slug], "Setting up")
        case .signIn:
            // A store whose token Cellar holds is signed in once, for the account — so the button
            // opens Accounts rather than pretending there is a per-game client to open.
            if game.store.descriptor.signsInOnce {
                NotificationCenter.default.post(name: .cellarOpenAccounts, object: nil)
            } else {
                act([game.store.rawValue, "open", game.slug], "Opening \(game.store.displayName)")
            }
        case .install:
            switch game.store {
            case .steam:      act(["steam", "install", game.slug], "Installing")
            case .battlenet:  act(["battlenet", "open", game.slug], "Opening Battle.net")
            case .gog:        act(["gog", "install", game.slug], "Downloading from GOG")
            case .standalone: copyDownloadCommand()
            }
        }
    }

    private func copyDownloadCommand() {
        let command = "cellar fetch-depot \(game.slug) --username <your-steam-account>"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        runner.note("Copied to the clipboard:\n$ \(command)\nRun it in Terminal — Steam Guard needs one.")
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
