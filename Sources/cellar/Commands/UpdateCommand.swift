import ArgumentParser
import CellarKit
import Foundation

/// Keep the games Cellar downloaded itself on Steam's current build.
///
/// A game Steam installed is Steam's to update. One Cellar fetched straight from the depots is not
/// in Steam's library, so Steam never patches it — Play checks and catches it up on its way to the
/// game, and this is the same thing by hand, or for every game at once.
struct UpdateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Check the games Cellar downloaded for a newer build, and download only what changed.",
        discussion: """
        Play already does this before it starts a game. Games installed through the Steam client
        are left to Steam, which updates them itself.
        """)

    @Argument(help: "Profile slug. Leave it out to check every game Cellar downloaded.")
    var slug: String?

    @Flag(help: "Only ask Steam and report; download nothing.")
    var check = false

    @Flag(name: .customLong("machine-progress"),
          help: "Also print a marker line as the update moves through its steps, for the Cellar app's progress bar.")
    var machineProgress = false

    func run() throws {
        let plans: [GamePlan]
        if let slug {
            let plan = try Game.plan(slug: slug)
            guard GameUpdates.managesUpdates(plan) else {
                print(Self.notManaged(plan))
                return
            }
            plans = [plan]
        } else {
            plans = ProfileStore.all().compactMap { try? Game.plan(slug: $0.slug) }
                .filter(GameUpdates.managesUpdates)
            if plans.isEmpty {
                print("No games to check — Cellar hasn't downloaded any itself. Steam keeps the ones it installed up to date.")
                return
            }
        }

        var last: InstallProgress?
        func report(_ progress: InstallProgress) {
            guard machineProgress else { return }
            if let was = last?.fraction, let now = progress.fraction, last?.phase == progress.phase,
               abs(now - was) < 0.001 { return }
            last = progress
            print(InstallMarker.line(progress))
        }

        var failed = false
        for plan in plans {
            print(Term.bold(plan.name) + Term.dim("  — asking Steam which build is current…"))
            report(InstallProgress(.updateCheck))
            switch GameUpdates.check(plan) {
            case .upToDate:
                print("  " + Term.green("Up to date."))
            case .unknown(let why):
                print("  " + Term.yellow("Couldn't check: ") + why)
                failed = true
            case .available:
                guard !check else {
                    print("  " + Term.yellow("A newer version is out.") + " Download it with: cellar update \(plan.slug)")
                    continue
                }
                print("  A newer version is out — downloading only what changed…")
                do {
                    try GameUpdates.apply(plan, progress: { print("    " + Term.dim($0)) }, phase: report)
                    print("  " + Term.green("Updated."))
                } catch GameUpdates.UpdateFailure.notStarted(let why) {
                    print("  " + Term.yellow("Couldn't start the update: ") + why + Term.dim(" — the version on disk is untouched."))
                    failed = true
                } catch {
                    print("  " + Term.red("The update stopped partway: ") + CellarLog.describe(error)
                        + ". Run it again to pick up where it left off: cellar update \(plan.slug)")
                    failed = true
                }
            }
        }
        if failed { throw ExitCode(1) }
    }

    static func notManaged(_ plan: GamePlan) -> String {
        if let appID = plan.appID, SteamBottle.isGameInstalled(in: plan.prefix, appID: appID) {
            return "\(plan.name) is in Steam's own library, so Steam keeps it up to date."
        }
        if !Game.isGameInstalled(plan) {
            return "\(plan.name) isn't installed. Install it with: cellar install \(plan.slug)"
        }
        return "\(plan.name) didn't come from Cellar's Steam download, so there's nothing for Cellar to update."
    }
}
