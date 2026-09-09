import ArgumentParser
import CellarKit

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check that your Mac is ready to run Windows games with Cellar."
    )

    func run() throws {
        print(Term.bold("Cellar doctor") + Term.dim(" — environment diagnostics"))
        print("")

        let checks = SystemEnvironment.diagnostics()
        for check in checks {
            let name = check.name.padding(toLength: 20, withPad: " ", startingAt: 0)
            print("  \(Term.symbol(for: check.status)) \(name) \(check.detail)")
            if let hint = check.hint {
                print("      " + Term.dim("→ \(hint)"))
            }
        }
        print("")

        // Where the player stands with the stores, since that is what "am I ready to play?" actually
        // depends on once the machine itself is fine. Full detail: cellar accounts.
        print(Term.bold("Store accounts") + Term.dim("  (detail: cellar accounts)"))
        if let account = SteamBottle.sharedLoggedInAccount {
            print("  \(Term.green("✓")) Steam        signed in as \(account), shared by every Steam game")
        } else if SteamBottle.isSharedInstallPresent {
            print("  \(Term.yellow("•")) Steam        installed but not signed in — cellar steam open <slug>")
        } else {
            print("  \(Term.dim("·")) Steam        no shared install yet — created by: cellar setup --profile <slug>")
        }
        if GOGAuth.isSignedIn {
            print("  \(Term.green("✓")) GOG          signed in\(GOGAuth.cachedUsername.map { " as \($0)" } ?? "")")
        } else {
            print("  \(Term.dim("·")) GOG          not signed in — cellar gog login")
        }
        // A bottle still carrying its own Steam copy is wasted space the player should know about.
        let unshared = ((try? PrefixManager.list()) ?? []).filter {
            SteamBottle.hasOwnSteamInstallForDiagnostics(in: $0.url)
        }
        if !unshared.isEmpty {
            print("  \(Term.yellow("•")) \(unshared.count) bottle(s) still keep their own Steam copy — cellar steam share")
        }
        print("")

        let fails = checks.filter { $0.status == .fail }.count
        let warns = checks.filter { $0.status == .warn }.count
        if fails == 0 && warns == 0 {
            print(Term.green("All systems go.") + " Ready for Phase 1 (prefix + Steam install).")
        } else {
            print("\(fails) blocking, \(warns) warning(s). Resolve blocking items before continuing.")
        }
    }
}
