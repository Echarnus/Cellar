import AppKit
import Combine
import Observation
import Sparkle

/// Cellar updating itself, through Sparkle.
///
/// The feed is the newest GitHub release's `appcast.xml`, and every archive in it is signed with an
/// EdDSA key whose public half is in Info.plist — Sparkle refuses an update that key did not sign.
/// Both keys are written by `Scripts/package.sh` only for a release build. A build from source has
/// neither, so it never offers to replace itself with a release: `isAvailable` is false, the menu
/// item is left out and Settings says why.
///
/// Automatic checks are the player's choice. Info.plist leaves `SUEnableAutomaticChecks` unset, so
/// Sparkle asks once — on the second launch, not the first, which already has the welcome tour.
///
/// One instance, made by `AppModel` the first time the menu bar asks for it.
@Observable
final class AppUpdater {

    /// Nil when this build carries no feed or no signing key.
    private let controller: SPUStandardUpdaterController?

    private(set) var canCheck = false
    private(set) var lastChecked: Date?
    var checksAutomatically = false {
        didSet {
            guard let updater, updater.automaticallyChecksForUpdates != checksAutomatically else { return }
            updater.automaticallyChecksForUpdates = checksAutomatically
        }
    }

    var isAvailable: Bool { controller != nil }
    private var updater: SPUUpdater? { controller?.updater }

    @ObservationIgnored private var subscriptions: Set<AnyCancellable> = []

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String) ?? ""
        let key = (info["SUPublicEDKey"] as? String) ?? ""
        guard !feed.isEmpty, !key.isEmpty else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        guard let updater else { return }
        // KVO, delivered on the main thread by Sparkle's own changes — never from inside a view
        // update, which this app's hosting view cannot survive (skills/swift.md).
        updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheck = $0 }.store(in: &subscriptions)
        updater.publisher(for: \.lastUpdateCheckDate).receive(on: RunLoop.main)
            .sink { [weak self] in self?.lastChecked = $0 }.store(in: &subscriptions)
        updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main)
            .removeDuplicates().sink { [weak self] in self?.checksAutomatically = $0 }.store(in: &subscriptions)
    }

    /// Shows Sparkle's own window: "You're up to date", or the new version's notes and an Install
    /// button. Nothing is downloaded or replaced until the player says so.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// "Check for Updates…" for the app menu, or nil for a build that cannot update itself.
    /// Sparkle's controller validates the item, so it greys out while a check is already running.
    func makeMenuItem() -> NSMenuItem? {
        guard let controller else { return nil }
        let item = NSMenuItem(title: String(localized: "Check for Updates…"),
                              action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                              keyEquivalent: "")
        item.target = controller
        return item
    }
}
