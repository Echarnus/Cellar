import CellarDomain
import ArgumentParser
import CellarData
import Foundation

struct NetworkCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "network",
        abstract: "Check that a game can get online from inside its bottle (workshops, online features).",
        discussion: """
        Asks each service the game needs twice — once through the same Windows network stack the game
        uses, inside its bottle, and once from your Mac — and says whose problem a failure is: your
        connection, the service, or Cellar's layer.

          cellar network planet-coaster-2
        """
    )

    @Argument(help: "Profile slug to check, e.g. 'planet-coaster-2'.")
    var slug: String

    func run() throws {
        let plan = try Game.plan(slug: slug)
        guard let wine = Game.wineRunner(plan) else {
            throw CellarError.invalidArgument(
                "Runner '\(plan.runnerID)' isn't installed. Run: cellar setup --profile \(slug)")
        }
        guard FileManager.default.fileExists(atPath: plan.prefix.path) else {
            throw CellarError.invalidArgument(
                "\(plan.name) has no bottle yet. Run: cellar setup --profile \(slug)")
        }
        let fromProfile = ProfileStore.find(slug).flatMap { ProfileStore.fields($0)["network_check"] }
        let urls = NetworkCheck.urls(store: plan.store, profileValue: fromProfile)
        print("Checking \(urls.count) services \(plan.name) needs, from your Mac and from inside its bottle…")
        let results = NetworkCheck.run(wine, urls: urls)
        for result in results {
            let mark = result.bottle.reached ? Term.green("✓") : Term.red("✗")
            print("  \(mark) \(Term.bold(result.host))")
            print(Term.dim("      bottle: \(result.bottle.sentence)"))
            print(Term.dim("      Mac:    \(result.mac.sentence)"))
        }
        print("")
        print(NetworkCheck.verdict(results))
        if results.contains(where: \.layerIsInTheWay) { throw ExitCode(1) }
    }
}
