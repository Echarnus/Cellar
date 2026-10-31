import CellarDomain
import Foundation
import Observation
import CellarKit

/// Settings' own state: the facts its panes read from this Mac (the runner, the game database, what
/// Cellar takes on disk, the kept log) and the diagnostics export, in every state it can be in.
///
/// `SettingsView` owns one. Accounts, the library and the activity are the app's shared view
/// models and are handed to the view, not kept here.
@MainActor
@Observable
final class SettingsViewModel {
    /// Where the diagnostics export has got to. Every one of these states is drawn: a button that
    /// silently writes a file somewhere is a button the player can't trust.
    enum Export: Equatable {
        case idle, working
        case written(URL)
        case failed(String)
    }

    private(set) var export: Export = .idle
    /// Read after the first layout, never from the body (skills/swift.md).
    private(set) var databaseVersion = ""
    /// Measured off the main thread when the pane opens: walking a 100 GB game takes seconds.
    private(set) var storageUsage: [GameStorage.Usage] = []

    var runnerName: String { RunnerManager.installed().first?.spec.displayName ?? String(localized: "not installed") }
    var depot: String { DepotTool.isInstalled ? "installed" : String(localized: "installs on first download") }

    var logSize: String {
        let bytes = CellarLog.historySize
        if bytes == 0 { return String(localized: "nothing logged yet") }
        return bytes < 1024 ? String(localized: "\(bytes) bytes") : String(localized: "\(bytes / 1024) KB")
    }

    /// Which game database is in use: the one this Cellar shipped with, or a signed update.
    func refreshDatabase() {
        databaseVersion = Self.describeDatabase()
    }

    static func describeDatabase() -> String {
        guard let installed = ProfileUpdates.installed else { return String(localized: "The one Cellar \(CellarVersion.current) shipped with") }
        let fetched = installed.fetched.formatted(.relative(presentation: .named))
        return String(localized: "\(installed.count) profiles from Cellar \(installed.cellarVersion), fetched \(fetched)")
    }

    func measureStorage() {
        Task.detached(priority: .utility) {
            let usage = GameStorage.usage()
            await MainActor.run { self.storageUsage = usage }
        }
    }

    /// Off the main thread: the report shells out to `sysctl`, `arch` and `gh`, and a Settings
    /// window that beachballs while doing it would be its own bug.
    func exportReport(cellarVersion version: String) {
        export = .working
        Task.detached {
            do {
                let url = try Diagnostics.exportReport(cellarVersion: version)
                await MainActor.run { self.export = .written(url) }
            } catch {
                await MainActor.run { self.export = .failed(CellarLog.describe(error)) }
            }
        }
    }
}
