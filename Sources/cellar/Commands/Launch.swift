import ArgumentParser
import CellarKit

struct Launch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch a game from its profile. [Phase 1]"
    )

    @Argument(help: "Profile slug to launch, e.g. 'planet-coaster-2'.")
    var slug: String

    func run() throws {
        guard ProfileStore.find(slug) != nil else {
            throw CellarError.invalidArgument("No profile '\(slug)'. Try: cellar profiles list")
        }
        print(Term.yellow("Not yet implemented (Phase 1).")
            + " Will launch '\(slug)' through its bottle + backend.")
    }
}
