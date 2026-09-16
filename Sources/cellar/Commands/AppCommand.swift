import ArgumentParser
import CellarKit

struct AppCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app",
        abstract: "Add the game to ~/Applications as '<Game>.app', with the game's own icon.",
        discussion: """
        Works for every store. The app opens the game the same way Play does (`cellar launch`), \
        and shows up in Launchpad and Spotlight under the game's name, not the store's.
        """)

    @Argument(help: "Profile slug.") var slug: String

    func run() throws {
        let plan = try Game.plan(slug: slug)
        let bundle = try AppBundle.generate(for: plan, cellarBinary: AppBundle.resolveCellarBinary())
        print(Term.green("Added ") + bundle.app.path)
        if !bundle.hasIcon {
            print(Term.dim("It has a plain icon for now — the game's own appears once \(plan.name) is installed. "
                + "Run this again then."))
        }
    }
}
