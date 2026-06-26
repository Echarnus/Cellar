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

        let fails = checks.filter { $0.status == .fail }.count
        let warns = checks.filter { $0.status == .warn }.count
        if fails == 0 && warns == 0 {
            print(Term.green("All systems go.") + " Ready for Phase 1 (prefix + Steam install).")
        } else {
            print("\(fails) blocking, \(warns) warning(s). Resolve blocking items before continuing.")
        }
    }
}
