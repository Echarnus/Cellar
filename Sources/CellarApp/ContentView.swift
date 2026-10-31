import SwiftUI
import AppKit
import CellarKit
import CellarUI

struct ContentView: View {
    /// The app's one library (`AppModel`), shared with Settings and the welcome tour.
    @Bindable var lib: LibraryStore
    /// The app's one activity, shared with Settings and the welcome tour (`AppModel`).
    let runner: ActivityStore
    let preparation: RuntimePreparation
    @FocusState private var searchFocused: Bool

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 272, maxWidth: 340)
            Group {
                if let game = lib.current {
                    GameDetailView(game: game, runner: runner) { lib.refresh() }.id(game.slug)
                } else { EmptyState() }
            }.frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 880, minHeight: 580)
        .onAppear { lib.refresh() }
        .task { await keepGamesCurrent() }
        .onReceive(NotificationCenter.default.publisher(for: .cellarFocusSearch)) { _ in
            searchFocused = true
        }
    }

    /// When the game database was last fetched, so the daily check survives a relaunch.
    @AppStorage("profilesLastChecked") private var lastDatabaseCheckStamp: Double = 0
    private var lastDatabaseCheck: Date {
        get { Date(timeIntervalSince1970: lastDatabaseCheckStamp) }
        nonmutating set { lastDatabaseCheckStamp = newValue.timeIntervalSince1970 }
    }

    /// How old an answer from Steam may get before the app asks again.
    private static let updateCheckInterval = GameUpdates.recheckInterval

    /// Keeps each downloaded game's "up to date / update available" honest while the app is open, by
    /// asking Steam about any game whose last answer is stale. It only asks: the download itself
    /// happens on Play (which catches the game up before starting it) or on "Update now", where the
    /// player sees it coming. A patch started on its own would hold the app's one runner — and with
    /// it every Play button — for as long as it took, with nothing on screen to stop it.
    ///
    /// Skipped while Cellar is running anything, so a check never competes with a download or a game.
    private func keepGamesCurrent() async {
        while !Task.isCancelled {
            let due = lib.games
                .filter { $0.update != nil && !GameUpdates.isFresh($0.update, within: Self.updateCheckInterval) }
                .map(\.slug)
            if !due.isEmpty, !runner.busy {
                for slug in due {
                    _ = await runner.runBeside(.checkForUpdate(slug: slug))
                }
                lib.refresh()
            }
            // The game database, once a day, the same quiet way. A build with no signing key has
            // nothing it could accept, so it doesn't ask.
            if !ProfileUpdates.publicKey.isEmpty, !runner.busy,
               Date().timeIntervalSince(lastDatabaseCheck) > 24 * 60 * 60 {
                lastDatabaseCheck = Date()
                if await runner.runBeside(.updateProfiles(quiet: true)) == 0 { lib.refresh() }
            }
            try? await Task.sleep(for: .seconds(30 * 60))
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            header
            searchField
            if lib.presentStores.count > 1 { storeChips }
            stateFilter
            libraryList
            Divider()
            footer
        }
        // The system's sidebar material, not a flat fill: it is translucent to the desktop behind
        // the window and follows light, dark and Increase Contrast by itself, as Finder's does.
        .background(SidebarMaterial().ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 8) {
            KegMark(size: 18).foregroundStyle(.pink)
            Text("Cellar").font(.system(.title3, design: .rounded).weight(.bold))
            Spacer()
            Button { lib.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Refresh the library (⌘R)")
                .accessibilityLabel("Refresh the library")
            // Accounts sits beside Settings because signing in is a thing you do once, for the
            // whole library — not something to rediscover on each game's screen.
            Button { NotificationCenter.default.post(name: .cellarOpenAccounts, object: nil) }
                label: { Image(systemName: "person.crop.circle") }
                .buttonStyle(.borderless).help("Accounts — sign in to Steam, GOG and Battle.net (⌘⇧A)")
                .accessibilityLabel("Accounts")
            Button { NotificationCenter.default.post(name: .cellarOpenSettings, object: nil) }
                label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help("Settings (⌘,)")
                .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
            TextField("Search games", text: $lib.query.text).textFieldStyle(.plain)
                .focused($searchFocused)
                // Escape clears and leaves the field, as Finder's search does.
                .onExitCommand { lib.query.text = ""; searchFocused = false }
                .accessibilityLabel("Search games")
            if !lib.query.text.isEmpty {
                Button { lib.query.text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("Clear search")
                    .accessibilityLabel("Clear search")
                    .help("Clear search")
            }
        }
        .padding(7)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    /// The store scope. Chips rather than a menu: which storefronts a library spans is worth
    /// seeing without opening anything, and it is how the second store announces itself.
    private var storeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(title: String(localized: "All stores"), tint: .secondary,
                           selected: lib.query.store == nil,
                           action: { lib.query.store = nil }) {
                    Image(systemName: "square.grid.2x2.fill").font(.caption2.weight(.semibold))
                }
                ForEach(lib.presentStores, id: \.self) { store in
                    FilterChip(title: store.displayName, tint: store.tint,
                               selected: lib.query.store == store,
                               action: { lib.query.store = (lib.query.store == store) ? nil : store }) {
                        StoreMark(store: store, size: 12)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 8)
    }

    private var stateFilter: some View {
        HStack(spacing: 6) {
            Picker("", selection: $lib.query.filter) {
                ForEach(LibraryStore.Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .accessibilityLabel("Filter by readiness")
            Menu {
                Picker("Sort by", selection: $lib.query.sort) {
                    ForEach(LibraryStore.Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(lib.query.sort == .name ? Text("Sort by name") : Text("Sort by most recently played"))
            .accessibilityLabel(lib.query.sort == .name ? Text("Sort, currently by name") : Text("Sort, currently by most recently played"))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var libraryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3, pinnedViews: [.sectionHeaders]) {
                ForEach(lib.sections, id: \.id) { section in
                    Section {
                        ForEach(section.games) { game in
                            SidebarRow(game: game, selected: lib.selected == game.slug)
                                .contentShape(Rectangle())
                                .onTapGesture { lib.selected = game.slug }
                        }
                    } header: {
                        StoreSectionHeader(store: section.store, count: section.games.count, guessed: section.guessed)
                    }
                }
                if lib.filtered.isEmpty { emptyLibrary }
                withheldNotice
            }
            .padding(8)
        }
        // The keyboard reaches the list: click in it (or Tab to it) and ↑/↓ walk the games, the
        // way every Mac sidebar works. Return then presses Play — it is the default button.
        .focusable()
        .noFocusRing()
        .onMoveCommand { direction in
            switch direction {
            case .up: lib.moveSelection(by: -1)
            case .down: lib.moveSelection(by: 1)
            default: break
            }
        }
    }

    /// Games are being withheld because a store hasn't been asked yet — say so, in the library,
    /// where they would have been.
    ///
    /// This has to sit *below* the sections rather than only in the empty state: one Battle.net game
    /// is enough to make the library non-empty, and then five Steam games and a GOG game go missing
    /// with nothing on screen to explain it. A count and the action is the whole fix.
    ///
    /// Only until a store is connected, though: a player signed in to one store has already found
    /// Accounts, and a standing "sign in" under their games reads as though that sign-in failed.
    @ViewBuilder private var withheldNotice: some View {
        if !lib.withheld.isEmpty, !lib.games.isEmpty, !lib.hasConnectedStore {
            VStack(alignment: .leading, spacing: 6) {
                Divider().padding(.vertical, 4)
                (lib.withheld.count == 1 ? Text("1 more game once you sign in")
                    : Text("\(lib.withheld.count) more games once you sign in"))
                    .font(.caption.weight(.semibold))
                // The same sentence the empty state uses, so a player who sees both is told the
                // same thing twice rather than two different things once.
                Text(lib.signInReason)
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Sign in") {
                    NotificationCenter.default.post(name: .cellarOpenAccounts, object: nil)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, 10).padding(.bottom, 10)
        }
    }

    /// The empty library is where a player finds out *why* their games aren't here — so it carries
    /// the reason and the single action that fixes it, not an apology.
    @ViewBuilder private var emptyLibrary: some View {
        VStack(spacing: 8) {
            switch emptyState {
            case .noMatches:
                Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text("No games match").font(.callout.weight(.semibold))
                if lib.isFiltered {
                    Text("Nothing in your library fits this search and these filters.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Clear filters") { lib.clearFilters() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            case .checking(let sentence):
                // Signed in, answers still coming: the one state that must never read as "sign in".
                ProgressView().controlSize(.small)
                Text("Checking your library").font(.callout.weight(.semibold))
                Text(sentence)
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            case .unchecked:
                Text("Your library hasn't been checked yet").font(.callout.weight(.semibold))
                Text("You're signed in. Cellar lists a game once its store confirms you own it.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                checkLibraryButton("Check now").buttonStyle(.borderedProminent)
            case .nothingOwned:
                Text("Nothing here yet.").font(.callout.weight(.semibold))
                Text("Signed in, but none of the games Cellar supports are in your library.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                checkLibraryButton("Check again").buttonStyle(.bordered)
            case .signIn:
                // Which store is actually missing decides the sentence. Telling a GOG-only player
                // to scan a Steam QR code names the wrong problem *and* the wrong fix.
                Text("Sign in to see your games").font(.callout.weight(.semibold))
                Text(lib.signInReason)
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Sign in") {
                    NotificationCenter.default.post(name: .cellarOpenAccounts, object: nil)
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                if !lib.withheld.isEmpty {
                    (lib.withheld.count == 1 ? Text("1 supported game is waiting behind it.")
                        : Text("\(lib.withheld.count) supported games are waiting behind it."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 24).padding(.horizontal, 8)
    }

    private static let checkingTitle = String(localized: "Checking your library")

    private var emptyState: StoreLibrary.EmptyLibrary {
        // The sidebar's own "Check now" is a check in progress too.
        let ownCheck = runner.busy && runner.busyTitle == Self.checkingTitle
            ? String(localized: "Asking your stores which games you own…") : nil
        return StoreLibrary.emptyLibrary(
            hasGames: !lib.games.isEmpty,
            checking: lib.checking ?? ownCheck,
            hasConnectedStore: lib.hasConnectedStore,
            uncheckedWithheld: lib.withheld.filter(StoreLibrary.isUnchecked).count)
    }

    private func checkLibraryButton(_ title: String) -> some View {
        Button(title) {
            runner.run(.refreshLibrary, title: Self.checkingTitle, then: { lib.refresh() })
        }
        .controlSize(.small).disabled(runner.busy)
    }

    private var footer: some View {
        HStack {
            // While the shared parts download, that is the news; the game count can wait.
            if preparation.isWorking {
                PreparationStatus(preparation: preparation)
            } else {
                Text(footerText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !runner.binaryExists {
                Label("CLI missing", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .help("Cellar drives the `cellar` command-line tool. Install it with Scripts/install-app.sh.")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var footerText: String {
        let games = lib.games.count
        let stores = lib.presentStores.count
        let gameCount = games == 1 ? String(localized: "1 game") : String(localized: "\(games) games")
        return stores > 1 ? String(localized: "\(gameCount) · \(stores) stores") : gameCount
    }
}

/// A store's heading in the library. Carries the mark *and* the word, so the section — not each
/// row — is what tells you where these games come from.
struct StoreSectionHeader: View {
    let store: GameStore
    let count: Int
    var guessed = false

    var body: some View {
        HStack(spacing: 6) {
            StoreMark(store: store, size: 13)
            Text(store.descriptor.sectionTitle.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(store.tint)
                .kerning(0.6)
            if guessed {
                Text("· UNTESTED, CELLAR GUESSED")
                    .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    .kerning(0.6).lineLimit(1)
                    .help("Cellar wrote these games' settings itself from their files. Nobody has tested them yet.")
            }
            Text("\(count)")
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 4)
        // The same material as the sidebar under it, so a pinned heading reads as part of the
        // sidebar rather than an opaque strip floating over it.
        .background(SidebarMaterial())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenHeading(store: store.displayName, guessed: guessed, count: count))
    }

    /// Whole sentences per case, so a translation never has to fit English words around a number.
    static func spokenHeading(store: String, guessed: Bool, count: Int) -> String {
        switch (guessed, count == 1) {
        case (false, true):  return String(localized: "\(store), 1 game")
        case (false, false): return String(localized: "\(store), \(count) games")
        case (true, true):   return String(localized: "\(store), untested, settings guessed by Cellar, 1 game")
        case (true, false):  return String(localized: "\(store), untested, settings guessed by Cellar, \(count) games")
        }
    }
}

struct FilterChip<Icon: View>: View {
    let title: String
    let tint: Color
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let icon: Icon
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                icon
                Text(title).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(selected ? .white : tint)
            .background(selected ? AnyShapeStyle(tint)
                                 : AnyShapeStyle(tint.opacity(hovering ? 0.22 : 0.13)),
                        in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct SidebarRow: View {
    let game: GameSummary
    let selected: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 11) {
            GameCover(game: game, width: 34)
                .padding(.trailing, 4)   // room for the badge that overhangs the cover
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name).lineLimit(1).font(.callout.weight(.medium))
                StatusPill(game: game, compact: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(selected ? Color.accentColor.opacity(contrast == .increased ? 0.40 : 0.20)
                             : (hovering ? Color.primary.opacity(contrast == .increased ? 0.14 : 0.06) : Color.clear),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hover in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { hovering = hover } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(game.name), \(game.store.displayName), \(game.statusText)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }
}

extension GameSummary {
    /// One word for where this game stands, shared by the pill and by VoiceOver.
    var statusText: String {
        switch nextStep {
        case .setup:   return String(localized: "Needs repair")
        case .install: return String(localized: "Not installed")
        case .play:    return String(localized: "Installed")
        }
    }

    var statusSymbol: String {
        switch nextStep {
        case .setup:   return "wrench.and.screwdriver"
        case .install: return "arrow.down.circle"
        case .play:    return "checkmark.circle.fill"
        }
    }

    var statusTint: Color {
        switch nextStep {
        case .setup:   return .orange
        case .install: return .secondary
        case .play:    return .green
        }
    }
}

struct StatusPill: View {
    let game: GameSummary
    var compact = false

    var body: some View {
        if compact {
            Text(game.statusText).font(.caption2).foregroundStyle(game.statusTint)
        } else {
            Text(game.statusText).font(.caption.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(game.statusTint, in: Capsule())
        }
    }
}

/// The sidebar's translucent material. `NSVisualEffectView` rather than a SwiftUI `Material`,
/// because only AppKit's `.sidebar` material is the exact one Finder and Mail use — and it adapts
/// to Reduce Transparency on its own.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension View {
    /// A list the keyboard can reach shouldn't draw a blue ring round the whole sidebar: the
    /// selected row is the focus indicator, as in Finder.
    func noFocusRing() -> some View {
        focusEffectDisabled()
    }
}

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            KegMark(size: 64, style: .outline).foregroundStyle(.pink.gradient)
            Text("Choose a game").font(.title2.weight(.semibold))
            Text("Windows games, running on your Mac.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
