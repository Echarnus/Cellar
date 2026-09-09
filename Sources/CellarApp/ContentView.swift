import SwiftUI
import AppKit
import CellarKit

@MainActor
final class Library: ObservableObject {
    /// **The games this player may see** — already filtered by `LibraryAccess`, so nothing
    /// downstream has to remember the rule. A library is your games; a catalogue of everything
    /// Cellar could run is a different screen, and not this one.
    @Published var games: [GameSummary] = []
    /// Which stores are connected and what each says the player owns. Read from disk and the
    /// keychain only — the network call that fills it is `refreshFromStores()`.
    @Published var access = LibraryAccess(statuses: [:])
    /// True while a store is being asked what the player owns, so the sidebar can say so instead of
    /// looking briefly empty — an empty library is exactly what this screen must not imply falsely.
    @Published var isReadingStores = false
    @Published var query = ""
    @Published var filter: Filter = .all
    /// nil means "every store". The library's primary axis: which client a game needs decides
    /// what every button in the app will do next.
    @Published var storeFilter: GameStore?
    @Published var selected: String? {
        didSet {
            // Reopening the app where you left it is the least a library can do.
            if let selected { UserDefaults.standard.set(selected, forKey: Library.lastSelectedKey) }
        }
    }

    static let lastSelectedKey = "lastSelectedGame"

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", ready = "Ready", installed = "Installed", notInstalled = "Not installed"
        var id: String { rawValue }
    }

    /// Re-read everything that can be read locally: sign-in state, cached libraries, and each
    /// game's readiness. Cheap enough for a button; no network, by design.
    func refresh() {
        access = StoreLibrary.access()
        games = Game.summaries().filter { access.isVisible($0) }
        guard selected == nil || !games.contains(where: { $0.slug == selected }) else { return }
        let remembered = UserDefaults.standard.string(forKey: Library.lastSelectedKey)
        if let remembered, games.contains(where: { $0.slug == remembered }) {
            selected = remembered
        } else {
            selected = filtered.first?.slug ?? games.first?.slug
        }
    }

    /// Ask each connected store what the player owns, then re-read.
    ///
    /// Off the main thread and never during layout: this makes HTTP calls, and mutating state
    /// inside `NSHostingView`'s first layout pass is what this app aborts on (skills/swift.md).
    /// Only stores whose cache is missing or a day old are asked, so opening the window does not
    /// hammer anybody's API.
    func refreshFromStores(force: Bool = false) {
        guard !isReadingStores else { return }
        let stores = force ? StoreLibrary.access().connectedStores.filter(\.canReportOwnership)
                           : StoreLibrary.storesNeedingRefresh()
        guard !stores.isEmpty else { return }
        isReadingStores = true
        Task.detached {
            for store in stores { _ = try? StoreLibrary.refresh(store) }
            await MainActor.run {
                self.isReadingStores = false
                self.refresh()
            }
        }
    }

    var filtered: [GameSummary] {
        games.filter { game in
            (storeFilter == nil || game.store == storeFilter)
                && (query.isEmpty || game.name.localizedCaseInsensitiveContains(query))
                && {
                    switch filter {
                    case .all: return true
                    case .ready: return game.nextStep == .play
                    case .installed: return game.gameInstalled
                    case .notInstalled: return !game.gameInstalled
                    }
                }()
        }
    }

    /// One store's block in the sidebar: its games, and the sentence that has to sit under the
    /// heading when Cellar could not check what the player owns.
    struct StoreSection: Identifiable {
        let store: GameStore
        let games: [GameSummary]
        /// nil when there is nothing to explain. Otherwise the honest note from `StoreStatus`.
        let note: String?
        /// True when the note is worth a button rather than just a sentence — Steam, before the
        /// player has given Cellar a way to read their library.
        let offersLibraryFix: Bool
        var id: GameStore { store }
    }

    /// The filtered library, grouped into store sections in a fixed order — never alphabetical,
    /// so a game doesn't move house when it is renamed.
    ///
    /// A connected store keeps its section even with nothing in it, as long as it has something to
    /// say. That empty section is the whole point: it is where a player finds out *why* their Steam
    /// games aren't listed and what to do about it, instead of concluding Cellar is broken.
    var sections: [StoreSection] {
        GameStore.allCases
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap { store in
                let inStore = filtered.filter { $0.store == store }.sorted { $0.name < $1.name }
                let status = access.status(store)
                let note = store == .standalone ? nil : status.libraryNote
                let isRealStore = store != .standalone
                guard !inStore.isEmpty || (isRealStore && status.isConnected && note != nil) else { return nil }
                return StoreSection(
                    store: store,
                    games: inStore,
                    note: note,
                    offersLibraryFix: store == .steam && status.library?.isComplete != true)
            }
    }

    /// Stores that actually have a game, so the filter never offers an empty result.
    var presentStores: [GameStore] {
        GameStore.allCases
            .sorted { $0.sortIndex < $1.sortIndex }
            .filter { store in games.contains { $0.store == store } }
    }

    var current: GameSummary? { games.first { $0.slug == selected } }
}

struct ContentView: View {
    @StateObject private var lib = Library()
    @StateObject private var runner = CellarRunner()

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 272, maxWidth: 340)
            Group {
                // Three states, in the order a new player meets them: nothing connected, connected
                // but nothing of theirs supported yet, and a game selected.
                if lib.access.hasNoConnection {
                    ConnectStoresView(runner: runner) { lib.refresh(); lib.refreshFromStores(force: true) }
                } else if let game = lib.current {
                    GameDetailView(game: game, runner: runner) { lib.refresh() }.id(game.slug)
                } else {
                    EmptyState(hasGames: !lib.games.isEmpty,
                               steamLibraryUnread: lib.access.status(.steam).isConnected
                                   && lib.access.status(.steam).library?.isComplete != true)
                }
            }.frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 880, minHeight: 580)
        .onAppear {
            lib.refresh()
            lib.refreshFromStores()
        }
        // Signing in happens in the Accounts window, which is a separate view graph — so the
        // library only learns about it if it is told. Without this, a player signs in and comes
        // back to the same empty screen.
        .onReceive(NotificationCenter.default.publisher(for: .cellarStoresChanged)) { _ in
            lib.refresh()
            lib.refreshFromStores(force: true)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            header
            // With no store connected there is nothing to search, filter or scroll. Showing the
            // controls anyway would be three dead widgets over an empty list; the one thing worth
            // saying is where the games will come from.
            if lib.access.hasNoConnection {
                notConnectedSidebar
            } else {
                searchField
                if lib.presentStores.count > 1 { storeChips }
                stateFilter
                libraryList
            }
            Divider()
            footer
        }
        .background(.background)
    }

    private var notConnectedSidebar: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 30, weight: .thin)).foregroundStyle(.secondary)
            Text("No games yet").font(.callout.weight(.medium))
            Text("Connect a store and the games you own appear here.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wineglass.fill").foregroundStyle(.pink)
            Text("Cellar").font(.system(.title3, design: .rounded).weight(.bold))
            Spacer()
            // One Refresh, and it does the whole job: re-read the bottles *and* ask each connected
            // store what you own. Two buttons for "the library might be out of date" would be a
            // distinction only Cellar's author cares about.
            Button { lib.refresh(); lib.refreshFromStores(force: true) }
                label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .disabled(lib.isReadingStores)
                .help("Refresh — re-check your bottles and ask each store what you own")
                .accessibilityLabel("Refresh the library")
            // Accounts sits beside Settings because signing in is a thing you do once, for the
            // whole library — not something to rediscover on each game's screen.
            Button { NotificationCenter.default.post(name: .cellarOpenAccounts, object: nil) }
                label: { Image(systemName: "person.crop.circle") }
                .buttonStyle(.borderless).help("Accounts — sign in to Steam, GOG and Battle.net")
                .accessibilityLabel("Accounts")
            Button { NotificationCenter.default.post(name: .cellarOpenSettings, object: nil) }
                label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help("Settings")
                .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
            TextField("Search games", text: $lib.query).textFieldStyle(.plain)
            if !lib.query.isEmpty {
                Button { lib.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .accessibilityLabel("Clear search")
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
                FilterChip(title: "All stores", tint: .secondary,
                           selected: lib.storeFilter == nil,
                           action: { lib.storeFilter = nil }) {
                    Image(systemName: "square.grid.2x2.fill").font(.system(size: 9, weight: .semibold))
                }
                ForEach(lib.presentStores, id: \.self) { store in
                    FilterChip(title: store.displayName, tint: store.tint,
                               selected: lib.storeFilter == store,
                               action: { lib.storeFilter = (lib.storeFilter == store) ? nil : store }) {
                        StoreMark(store: store, size: 12)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 8)
    }

    private var stateFilter: some View {
        Picker("", selection: $lib.filter) {
            ForEach(Library.Filter.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden()
        .padding(.horizontal, 12).padding(.vertical, 8)
        .accessibilityLabel("Filter by readiness")
    }

    private var libraryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3, pinnedViews: [.sectionHeaders]) {
                ForEach(lib.sections) { section in
                    Section {
                        if let note = section.note {
                            StoreLibraryNote(note: note,
                                             store: section.store,
                                             offersFix: section.offersLibraryFix)
                        }
                        ForEach(section.games) { game in
                            SidebarRow(game: game, selected: lib.selected == game.slug)
                                .contentShape(Rectangle())
                                .onTapGesture { lib.selected = game.slug }
                        }
                    } header: {
                        StoreSectionHeader(store: section.store, count: section.games.count)
                    }
                }
                if lib.sections.isEmpty {
                    Text(emptyListText)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity).padding(.top, 24).padding(.horizontal, 12)
                }
            }
            .padding(8)
        }
    }

    /// Why the list is empty, in the player's terms — never a bare "no results" for a state the
    /// player can act on.
    private var emptyListText: String {
        if lib.isReadingStores { return "Reading your library…" }
        if !lib.query.isEmpty || lib.filter != .all || lib.storeFilter != nil { return "No games match." }
        return "None of the games you own are ones Cellar supports yet."
    }

    private var footer: some View {
        HStack {
            if lib.isReadingStores { ProgressView().controlSize(.mini) }
            Text(footerText).font(.caption).foregroundStyle(.secondary)
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
        if lib.isReadingStores { return "Reading your library…" }
        if lib.access.hasNoConnection { return "No store connected" }
        let games = lib.games.count
        let stores = lib.presentStores.count
        let gameWord = games == 1 ? "game" : "games"
        let storeWord = stores == 1 ? "store" : "stores"
        return stores > 1 ? "\(games) \(gameWord) · \(stores) \(storeWord)" : "\(games) \(gameWord)"
    }
}

/// A store's heading in the library. Carries the mark *and* the word, so the section — not each
/// row — is what tells you where these games come from.
struct StoreSectionHeader: View {
    let store: GameStore
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            StoreMark(store: store, size: 13)
            Text(store.descriptor.sectionTitle.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(store.tint)
                .kerning(0.6)
            Text("\(count)")
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 4)
        .background(.background)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(store.displayName), \(count) \(count == 1 ? "game" : "games")")
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
        .background(selected ? Color.accentColor.opacity(0.20)
                             : (hovering ? Color.primary.opacity(0.06) : Color.clear),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hover in withAnimation(.easeOut(duration: 0.12)) { hovering = hover } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(game.name), \(game.store.displayName), \(game.statusText)")
    }
}

extension GameSummary {
    /// One word for where this game stands, shared by the pill, by VoiceOver and by
    /// `cellar library` — the wording itself lives in CellarKit so the two surfaces cannot drift.
    var statusText: String { statusWord }

    var statusTint: Color {
        switch nextStep {
        case .setup:   return .orange
        case .signIn:  return store.tint
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

/// The sentence under a store's heading when Cellar could not check what the player owns.
///
/// It sits *inside* the section rather than in a banner, because it explains that section and
/// nothing else — and for Steam it carries the fix, since a note about an unreadable library that
/// doesn't say how to make it readable is just an apology.
struct StoreLibraryNote: View {
    let note: String
    let store: GameStore
    let offersFix: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle").font(.caption2).foregroundStyle(.secondary)
                Text(note).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if offersFix {
                Button("Connect your \(store.displayName) library…") {
                    NotificationCenter.default.post(
                        name: .cellarOpenAccounts,
                        object: store == .steam ? AccountsFocus.steamLibrary : nil)
                }
                .buttonStyle(.link).font(.caption)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }
}

/// **First run: nothing is connected, so there is nothing to show.**
///
/// This is the screen that makes the gate feel like a front door rather than a locked one. One idea
/// per row — the store, what signing in gets you, and a button that starts it — and each button
/// does the real thing where it can, rather than sending the player somewhere else to find it.
struct ConnectStoresView: View {
    @ObservedObject var runner: CellarRunner
    let onChange: () -> Void
    @State private var gogFailure: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "wineglass")
                    .font(.system(size: 46, weight: .thin)).foregroundStyle(.pink.gradient)
                    .padding(.bottom, 14)
                Text("Sign in to see your games").font(.title2.weight(.semibold))
                Text("Cellar shows the Windows games you already own. Connect a store and yours appear here.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4).padding(.horizontal, 40)

                VStack(spacing: 10) {
                    ConnectStoreRow(
                        store: .steam,
                        detail: "Scan a QR code with the Steam app on your phone. Cellar never sees your password.",
                        actionTitle: "Sign in to Steam",
                        busy: runner.busy) {
                            NotificationCenter.default.post(name: .cellarOpenAccounts, object: nil)
                        }
                    ConnectStoreRow(
                        store: .gog,
                        detail: "Opens GOG in a window. One sign-in covers your whole GOG library.",
                        actionTitle: "Sign in to GOG",
                        busy: runner.busy) { signInToGOG() }
                    ConnectStoreRow(
                        // The honest one. Blizzard publishes neither who is signed in nor what they
                        // own, so there is nothing for Cellar to check — the player says so instead,
                        // and the button says exactly that rather than pretending to sign anyone in.
                        store: .battlenet,
                        detail: "Blizzard publishes neither your account nor your library, so Cellar can't check. Tell it you have one and its games appear.",
                        actionTitle: "I have an account",
                        busy: runner.busy) {
                            runner.run(["battlenet", "connect"], title: "Connecting Battle.net",
                                       then: onChange)
                        }
                }
                .frame(maxWidth: 520)
                .padding(.top, 26)

                if let gogFailure {
                    Text(gogFailure).font(.callout).foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12).padding(.horizontal, 40)
                }

                Text("Cellar only ever works with games you own. Your sign-ins stay in your keychain, on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 26).padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    /// GOG's sign-in is Cellar's own, so the welcome screen can run it here and now instead of
    /// handing the player off to another window to repeat the same click.
    private func signInToGOG() {
        gogFailure = nil
        GOGSignInWindow.present { result in
            switch result {
            case .code(let code):
                runner.run(["gog", "login", "--code", code], title: "Signing in to GOG", then: onChange)
            case .cancelled:
                break   // closing the window is a legitimate answer, not an error
            case .failed(let why):
                gogFailure = why
            }
        }
    }
}

/// One store's offer on the welcome screen: mark, name, one sentence, one button.
struct ConnectStoreRow: View {
    let store: GameStore
    let detail: String
    let actionTitle: String
    let busy: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StoreMark(store: store, size: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.displayName).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            // A common minimum so the three buttons share a right edge — three different widths
            // down the column reads as three unrelated controls rather than one choice.
            Button(action: action) { Text(actionTitle).frame(minWidth: 116) }
                .buttonStyle(.borderedProminent)
                .tint(store.tint)
                .disabled(busy)
        }
        .padding(14)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(store.displayName). \(detail)")
    }
}

/// A store is connected but no game is selected. Two different situations, and telling them apart
/// matters: "pick one from the left" is useless advice when the left is empty.
struct EmptyState: View {
    /// False when the gated library came back with nothing — the player is signed in, but none of
    /// the games Cellar could confirm are ones it supports.
    let hasGames: Bool
    /// True while Steam is connected without a way to read the library, which is the most likely
    /// reason a signed-in player is looking at an empty screen.
    let steamLibraryUnread: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: hasGames ? "wineglass" : "tray")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(hasGames ? AnyShapeStyle(Color.pink.gradient) : AnyShapeStyle(.secondary))
            Text(hasGames ? "Choose a game" : "Nothing to play yet")
                .font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
            if !hasGames, steamLibraryUnread {
                Button("Connect your Steam library…") {
                    NotificationCenter.default.post(name: .cellarOpenAccounts,
                                                    object: AccountsFocus.steamLibrary)
                }
                .buttonStyle(.borderedProminent).tint(GameStore.steam.tint)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(.background)
    }

    private var message: String {
        if hasGames { return "Windows games, running on your Mac." }
        return steamLibraryUnread
            ? "You're signed in, but Cellar can only list Steam games it can confirm you own. Give it a way to read your library and the rest appear here."
            : "You're signed in, but none of the games you own are ones Cellar supports yet. New profiles arrive with each release, and your games appear here on their own."
    }
}
