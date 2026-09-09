import SwiftUI
import AppKit
import CellarKit
import CellarUI

@MainActor
final class Library: ObservableObject {
    @Published var games: [GameSummary] = []
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

    /// Every profile Cellar ships that the player's stores did not confirm — kept only so the
    /// sidebar can say *how many* games are being withheld and why. Never rendered as a list: a
    /// list of games you don't own, presented in your library, is a claim no caption undoes.
    @Published var withheld: [GameSummary] = []
    /// The one Steam sign-in, so the empty state can name the fix rather than shrug.
    @Published var steam: SteamAccount.State = .signedOut

    func refresh() {
        // A store that has just been set up now has its own artwork on disk; re-resolve so its
        // mark upgrades from the drawn one to the store's own without needing a relaunch.
        StoreIcons.refresh()
        let all = Game.summaries()
        withheld = all.filter { !$0.isVisible }
        steam = SteamAccount.state
        games = all.filter(\.isVisible)
        guard selected == nil || !games.contains(where: { $0.slug == selected }) else { return }
        let remembered = UserDefaults.standard.string(forKey: Library.lastSelectedKey)
        if let remembered, games.contains(where: { $0.slug == remembered }) {
            selected = remembered
        } else {
            selected = filtered.first?.slug ?? games.first?.slug
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

    /// The filtered library, grouped into store sections in a fixed order — never alphabetical,
    /// so a game doesn't move house when it is renamed.
    var sections: [(store: GameStore, games: [GameSummary])] {
        GameStore.allCases
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap { store in
                let inStore = filtered.filter { $0.store == store }.sorted { $0.name < $1.name }
                return inStore.isEmpty ? nil : (store, inStore)
            }
    }

    /// Stores that actually have a game, so the filter never offers an empty result.
    var presentStores: [GameStore] {
        GameStore.allCases
            .sorted { $0.sortIndex < $1.sortIndex }
            .filter { store in games.contains { $0.store == store } }
    }

    var current: GameSummary? { games.first { $0.slug == selected } }

    /// Why the library is empty, named per store rather than assumed to be Steam's fault. Cellar
    /// speaks to three stores; only one of them signs in with a QR code.
    var signInReason: String {
        let allStores = Set(withheld.map(\.gatingStore))
        // Battle.net first, because it is the one store whose sentence is not about ownership at
        // all: Blizzard publishes nothing to check, so what is missing is the player's own word.
        if allStores == [.battlenet] {
            return "Blizzard publishes nothing Cellar can check, so it asks you instead. Add Battle.net and its games appear."
        }
        // Only games whose store was never *asked* say anything about signing in. A game the store
        // answered "no" to is withheld for a reason a sign-in cannot change — counting it here is
        // how a signed-in player gets told they are not signed in.
        let unasked = withheld.filter { game in
            if case .unknown = game.ownership { return game.gatingStore.canAnswerOwnership }
            return false
        }
        let stores = Set(unasked.map(\.gatingStore))
        if stores.contains(.steam), !steam.isUsable { return steam.summary }
        if stores == [.gog], !GOGAuth.isSignedIn {
            return "Not signed in to GOG. One sign-in covers your whole GOG library."
        }
        if stores.isEmpty {
            return "Nothing your stores confirmed you own is supported yet."
        }
        return "Cellar lists a game once its store confirms you own it, and it hasn't been able to ask yet."
    }
}

struct ContentView: View {
    @StateObject private var lib = Library()
    @StateObject private var runner = CellarRunner()

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
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wineglass.fill").foregroundStyle(.pink)
            Text("Cellar").font(.system(.title3, design: .rounded).weight(.bold))
            Spacer()
            Button { lib.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Refresh the library")
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
                ForEach(lib.sections, id: \.store) { section in
                    Section {
                        ForEach(section.games) { game in
                            SidebarRow(game: game, selected: lib.selected == game.slug)
                                .contentShape(Rectangle())
                                .onTapGesture { lib.selected = game.slug }
                        }
                    } header: {
                        StoreSectionHeader(store: section.store, count: section.games.count)
                    }
                }
                if lib.filtered.isEmpty { emptyLibrary }
                withheldNotice
            }
            .padding(8)
        }
    }

    /// Games are being withheld because a store hasn't been asked yet — say so, in the library,
    /// where they would have been.
    ///
    /// This has to sit *below* the sections rather than only in the empty state: one Battle.net game
    /// is enough to make the library non-empty, and then five Steam games and a GOG game go missing
    /// with nothing on screen to explain it. A count and the action is the whole fix.
    @ViewBuilder private var withheldNotice: some View {
        if !lib.withheld.isEmpty, !lib.games.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Divider().padding(.vertical, 4)
                Text("\(lib.withheld.count) more \(lib.withheld.count == 1 ? "game" : "games") once you sign in")
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
            if !lib.games.isEmpty {
                Text("No games match.").font(.caption).foregroundStyle(.secondary)
            } else if lib.steam.isUsable {
                Text("Nothing here yet.").font(.callout.weight(.semibold))
                Text("Signed in, but none of the games Cellar supports are in your library.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Check again") {
                    runner.run(["library", "--refresh"], title: "Checking your library",
                               then: { lib.refresh() })
                }
                .buttonStyle(.bordered).controlSize(.small)
            } else {
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
                    Text("\(lib.withheld.count) supported \(lib.withheld.count == 1 ? "game is" : "games are") waiting behind it.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 24).padding(.horizontal, 8)
    }

    private var footer: some View {
        HStack {
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
    /// One word for where this game stands, shared by the pill and by VoiceOver.
    var statusText: String {
        switch nextStep {
        case .setup:   return "Set-up needed"
        case .signIn:  return "Sign in"
        case .install: return "Not installed"
        case .play:    return "Ready"
        }
    }

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

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wineglass").font(.system(size: 52, weight: .thin)).foregroundStyle(.pink.gradient)
            Text("Choose a game").font(.title2.weight(.semibold))
            Text("Windows games, running on your Mac.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
