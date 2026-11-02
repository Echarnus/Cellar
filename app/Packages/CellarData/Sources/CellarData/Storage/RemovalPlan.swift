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

    /// The dialog's question, in the player's words.
    public var question: String {
        switch scope {
        case .bottle: return String(localized: "Remove \(name) completely?")
        case .game:
            return removesGameFiles ? String(localized: "Uninstall \(name)?")
                                    : String(localized: "Clean up what's left of \(name)?")
        }
    }

    /// What it frees and why it is safe, in plain sentences (Kenneth, #266). The itemised list —
    /// manifests, links, caches, the bottle and the runner by name — stays in `cellar uninstall`;
    /// a player deciding whether to click needs the size, and to know the game isn't gone for good.
    /// Never a command, a bottle or a runner.
    public var playerSummary: String {
        let size = totalSizeDescription
        let store = store.displayName
        switch scope {
        case .bottle:
            return String(localized: "Frees \(size) on this Mac. Cellar backs up your save games first. You still own \(name) on \(store), so you can download it again any time.")
        case .game where removesGameFiles:
            return String(localized: "Frees \(size) on this Mac. You still own \(name) on \(store), and your sign-in stays, so you can download it again any time.")
        case .game:
            return String(localized: "\(name) isn't installed. This frees the \(size) it left behind.")
        }
    }
}
