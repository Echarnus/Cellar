import CellarDomain
import ArgumentParser
import CellarKit
import Foundation

struct LanguageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "language",
        abstract: "Show or change the language games and their store clients run in.",
        discussion: """
        By default every game follows your Mac's language (System Settings → General → Language &
        Region). Pick another for every game, or for one game only. It applies from the next launch;
        a Steam that is already open keeps its language until it restarts.

          cellar language                                    what each game will use, and why
          cellar language list                               the languages Cellar can run a game in
          cellar language set english                        every game in English
          cellar language set dutch --game planet-coaster-2  just this game in Dutch
          cellar language reset                              every game follows your Mac again
          cellar language reset --game planet-coaster-2      this game follows the others again
        """,
        subcommands: [Show.self, List.self, Set.self, Reset.self],
        defaultSubcommand: Show.self
    )

    static func describe(_ choice: LanguageChoice) -> String {
        switch choice.source {
        case .system:   return "your Mac's language"
        case .allGames: return "your choice for every game"
        case .thisGame: return "your choice for this game"
        }
    }

    static func line(_ choice: LanguageChoice) -> String {
        Term.bold(choice.language.nativeName) + Term.dim("  (\(describe(choice)))")
    }

    static func language(_ text: String) throws -> GameLanguage {
        guard let language = GameLanguage.named(text) else {
            throw CellarError.invalidArgument(
                "Cellar can't run a game in '\(text)'. See the languages it can: cellar language list")
        }
        return language
    }

    /// The bottle a game's choice goes into — and the other games that will get it too.
    static func bottle(for plan: GamePlan) throws -> (url: URL, sharedWith: [String]) {
        // Creating a bare bottle here would make setup think it already exists and skip it.
        guard FileManager.default.fileExists(atPath: plan.prefix.path) else {
            throw CellarError.invalidArgument(
                "\(plan.name) has no bottle yet to keep this in. Run: cellar setup --profile \(plan.slug)  first.")
        }
        return (BottleConfig.url(forBottle: plan.bottleName),
                Game.slugs(sharingBottle: plan.bottleName).filter { $0 != plan.slug })
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show which language games will use.")

        @Option(name: .long, help: "Only this game (profile slug).")
        var game: String?

        func run() throws {
            if let game {
                let plan = try Game.plan(slug: game)
                print("\(plan.name): " + LanguageCommand.line(plan.language))
                return
            }
            print("Your Mac: " + Term.bold(GameLanguage.system().nativeName))
            print("Every game: " + LanguageCommand.line(LanguageChoice.global()))
            let own = ProfileStore.all().compactMap { try? Game.plan(slug: $0.slug) }
                .filter { $0.language.source == .thisGame }
            for plan in own {
                print("  \(plan.name): " + LanguageCommand.line(plan.language))
            }
            print(Term.dim("Change it: cellar language set <language> [--game <slug>]"))
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the languages Cellar can run a game in.")

        func run() throws {
            for language in GameLanguage.allCases {
                let code = language.code.padding(toLength: 8, withPad: " ", startingAt: 0)
                print("  \(code) \(language.nativeName)" + Term.dim("  \(language.steamName)"))
            }
            print(Term.dim("A game only has the languages its developer shipped; a missing one shows in English."))
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Pick a language for every game, or one.")

        @Argument(help: "A language: its code (nl), Steam's name (dutch) or its own name (Nederlands).")
        var language: String

        @Option(name: .long, help: "Only this game (profile slug).")
        var game: String?

        func run() throws {
            let chosen = try LanguageCommand.language(language)
            if let game {
                let plan = try Game.plan(slug: game)
                let (url, sharedWith) = try LanguageCommand.bottle(for: plan)
                try BottleConfig.setLanguage(chosen, in: url)
                let after = try Game.plan(slug: game)
                print(Term.green("Saved for \(plan.name), from the next launch: ") + LanguageCommand.line(after.language))
                if !sharedWith.isEmpty {
                    print(Term.dim("Shared bottle: \(sharedWith.joined(separator: ", ")) get this too."))
                }
            } else {
                try CellarSettings.setLanguage(chosen)
                print(Term.green("Every game, from its next launch: ") + LanguageCommand.line(LanguageChoice.global()))
            }
        }
    }

    struct Reset: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Follow your Mac's language again (or, with --game, the choice for every game).")

        @Option(name: .long, help: "Only this game (profile slug).")
        var game: String?

        func run() throws {
            if let game {
                let plan = try Game.plan(slug: game)
                try BottleConfig.setLanguage(nil, in: BottleConfig.url(forBottle: plan.bottleName))
                let after = try Game.plan(slug: game)
                print("\(after.name): " + LanguageCommand.line(after.language))
            } else {
                try CellarSettings.setLanguage(nil)
                print("Every game: " + LanguageCommand.line(LanguageChoice.global()))
            }
        }
    }
}
