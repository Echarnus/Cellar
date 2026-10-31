import CellarDomain
import ArgumentParser
import CellarData
import Foundation

struct ReportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Report how a game ran: prints the report, and opens GitHub's form with it filled in.",
        discussion: """
        Nothing is sent by Cellar. You read the report here, and with --open your browser shows
        GitHub's new-issue form with it filled in; you submit it there, or close the tab. Account
        names, your home folder and anything that looks like a token are taken out first.

          cellar report planet-coaster-2 --outcome works
          cellar report diablo-4 --outcome issues --notes "stutters in towns" --open
        """
    )

    @Argument(help: "Profile slug, e.g. 'planet-coaster-2'.")
    var slug: String

    @Option(name: .long, help: "works, issues or didnt-start.")
    var outcome: String

    @Option(name: .long, help: "What happened, in your words.")
    var notes: String?

    @Flag(name: .long, help: "Open the filled-in form in your browser.")
    var open = false

    func run() throws {
        guard let outcome = CompatibilityReport.Outcome(rawValue: outcome.lowercased()) else {
            let known = CompatibilityReport.Outcome.allCases.map(\.rawValue).joined(separator: ", ")
            throw CellarError.invalidArgument("'\(self.outcome)' isn't an outcome. Use one of: \(known)")
        }
        let facts = CompatibilityReport.Facts(try Game.plan(slug: slug), outcome: outcome, notes: notes)
        print(Term.bold(CompatibilityReport.title(facts)))
        print(CompatibilityReport.environment(facts))
        let details = CompatibilityReport.details(facts)
        if !details.isEmpty { print("\n" + details) }
        let url = CompatibilityReport.issueURL(facts)
        if open {
            _ = Shell.run("/usr/bin/open", [url.absoluteString])
            print(Term.dim("\nOpened GitHub's form in your browser. Nothing is filed until you submit it there."))
        } else {
            print(Term.dim("\nFile it (nothing is sent until you submit on GitHub):"))
            print(url.absoluteString)
        }
    }
}
