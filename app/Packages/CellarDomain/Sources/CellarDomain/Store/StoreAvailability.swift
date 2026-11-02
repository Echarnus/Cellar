import Foundation

/// **Which stores this build of Cellar offers** — the one switch for showing a store to players.
///
/// The first release is Steam only. Battle.net and GOG are fully built (their adapters, bottles,
/// sign-ins and CLI groups all stay), but a store that is not offered is hidden everywhere a player
/// looks: its games leave the library, its row leaves Accounts, its name leaves the copy that lists
/// the stores. Turning one back on is adding it to `offered` — nothing else should need to change.
///
/// Hiding, not gating: an un-offered store's games are dropped from the library outright rather
/// than withheld, because a withheld game comes with a fix ("Add Battle.net in Accounts") that the
/// player would then have no way to follow.
public enum StoreAvailability {
    /// The stores players see. Keep this in `GameStore.inLibraryOrder`'s order of thought; callers
    /// sort it anyway.
    public static let offered: Set<GameStore> = [.steam]

    /// "Steam", "Steam or GOG", "Steam, Battle.net or GOG" — the offered stores as a phrase, in
    /// library order, for copy that names them ("Everything installs from your own … account").
    public static func phrase(_ stores: [GameStore] = GameStore.offered) -> String {
        let names = stores.sorted { $0.sortIndex < $1.sortIndex }.map(\.displayName)
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        let rest = names.dropLast().joined(separator: ", ")
        return String(localized: "\(rest) or \(last)")
    }
}

public extension GameStore {
    /// Whether players see this store in this build (`StoreAvailability.offered`).
    var isOffered: Bool { StoreAvailability.offered.contains(self) }

    /// The offered stores, in library order.
    static var offered: [GameStore] { inLibraryOrder.filter(\.isOffered) }
}
