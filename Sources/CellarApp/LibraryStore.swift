import CellarDomain
import Foundation
import Observation
import CellarKit
import CellarUI

/// The library: which games the player has, which one is selected, and how the sidebar is narrowed.
///
/// One instance, made by `AppModel` and shared by every window, so a sign-in finishing in Settings
/// refreshes the same library the main window draws — a method call, not a notification someone has
/// to be listening for. What the sidebar *means* (filtering, sections, the empty-library sentence)
/// is decided by `LibraryQuery` and `LibrarySnapshot` in CellarKit, where it is unit-tested.
@MainActor
@Observable
final class LibraryStore {
    typealias Filter = LibraryQuery.Filter
    typealias Sort = LibraryQuery.Sort

    private(set) var snapshot = LibrarySnapshot.empty
    var games: [GameSummary] { snapshot.games }
    var withheld: [GameSummary] { snapshot.withheld }
    var steam: SteamAccount.State { snapshot.steam }
    var hasConnectedStore: Bool { snapshot.hasConnectedStore }
    var signInReason: String { snapshot.signInReason }

    /// The search field, the filters and the sort — bound straight to their controls.
    var query = LibraryQuery(sort: Sort(rawValue: UserDefaults.standard.string(forKey: LibraryStore.sortKey) ?? "") ?? .name) {
        didSet {
            if query.sort != oldValue.sort { UserDefaults.standard.set(query.sort.rawValue, forKey: Self.sortKey) }
        }
    }

    var selected: String? {
        didSet {
            // Reopening the app where you left it is the least a library can do.
            if let selected { UserDefaults.standard.set(selected, forKey: Self.lastSelectedKey) }
        }
    }

    /// A store's ownership check in progress, as its own progress sentence — set while a sign-in
    /// goes on to ask the store, cleared when the accounts change.
    private(set) var checking: String?

    static let lastSelectedKey = "lastSelectedGame"
    static let sortKey = "librarySort"

    @ObservationIgnored private let load: @MainActor () -> LibrarySnapshot

    /// `load` is the disk read; a test hands it a snapshot it built.
    init(load: @escaping @MainActor () -> LibrarySnapshot = { LibrarySnapshot.current() }) {
        self.load = load
    }

    // MARK: - Intents

    func refresh() {
        // A store that has just been set up now has its own artwork on disk; re-resolve so its
        // mark upgrades from the drawn one to the store's own without needing a relaunch.
        StoreIcons.refresh()
        snapshot = load()
        // What the sidebar just decided, on record: a reload that "does nothing" is otherwise
        // indistinguishable from one that ran and read a signed-out Steam.
        CellarLog.debug(.app, "Library refreshed: \(games.count) shown, \(withheld.count) withheld, \(hasConnectedStore ? "a store connected" : "no store connected") — \(SteamAccount.diagnosis)")
        guard selected == nil || !games.contains(where: { $0.slug == selected }) else { return }
        let remembered = UserDefaults.standard.string(forKey: Self.lastSelectedKey)
        if let remembered, games.contains(where: { $0.slug == remembered }) {
            selected = remembered
        } else {
            selected = filtered.first?.slug ?? games.first?.slug
        }
    }

    /// A store was signed in, signed out, added or removed: whatever was being checked is done, and
    /// which games are the player's may have changed.
    func accountsChanged() {
        checking = nil
        refresh()
    }

    /// A sign-in has gone on to ask the store which games are owned; `sentence` says so.
    func beganChecking(_ sentence: String?) {
        checking = sentence
    }

    /// Show one game, clearing anything that would hide it — the Dock menu's recent games.
    func show(_ slug: String) {
        guard games.contains(where: { $0.slug == slug }) else { return }
        query.store = nil
        query.text = ""
        selected = slug
    }

    func clearFilters() {
        query.text = ""
        query.filter = .all
        query.store = nil
    }

    /// The ↑/↓ keys in the sidebar: the next game in the order the player sees them.
    func moveSelection(by offset: Int) {
        selected = LibraryQuery.moving(selected, by: offset, in: sections.flatMap { $0.games.map(\.slug) })
    }

    // MARK: - Derived

    var filtered: [GameSummary] { query.filtered(games) }
    var sections: [LibrarySection] { query.sections(games) }
    var presentStores: [GameStore] { LibraryQuery.presentStores(in: games) }
    var current: GameSummary? { games.first { $0.slug == selected } }
    var isFiltered: Bool { query.isFiltered }
}
