import CellarDomain
import Foundation

/// Everything a removal would do, decided before it does any of it.
///
/// Deleting the wrong directory here costs a 90 GB re-download or a sign-in, so removal is a plan
/// first: paths resolved, sizes measured, what survives written down, and anything that makes the
/// removal unsafe raised as a blocker. The CLI prints it and asks; the app shows it in a dialog.
/// Neither of them decides *what* gets deleted — that lives here.
public struct RemovalPlan: Sendable {
    public let slug: String
    public let name: String
    public let store: GameStore
    public let bottleName: String
    public let scope: RemovalScope
    public let items: [RemovalItem]
    /// Sentences naming what deliberately survives. Shown every time: the biggest fear a player has
    /// about an uninstall button is that it takes their account or their other games with it.
    public let kept: [String]
    /// Things worth knowing before saying yes — none of them errors.
    public let warnings: [String]
    /// Why this cannot be carried out. Non-empty means nothing will be deleted; each one ends with
    /// the command or action that resolves it.
    public let blockers: [String]
    /// Whether carrying this out has to close the store's client in the bottle first. Announced up
    /// front, because a client vanishing mid-uninstall otherwise reads as a crash.
    public let closesStoreClient: Bool

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    public var isEmpty: Bool { items.isEmpty }
    /// Whether the game's own files are actually going. False when the game isn't installed and all
    /// that is left behind is something Cellar generated — a tidy-up, and worded as one.
    public var removesGameFiles: Bool { items.contains(where: \.isGameData) }
    public var canProceed: Bool { blockers.isEmpty && !isEmpty }

    /// "12.4 GB" — the number the player is actually deciding about.
    public var totalSizeDescription: String { ByteSize.describe(totalBytes) }
}
