import ArgumentParser
import CellarKit
import Foundation

struct ProfileCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "profiles",
        abstract: "Browse the per-game profile database.",
        subcommands: [List.self, Show.self, Update.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List available game profiles.")

        func run() throws {
            let profiles = ProfileStore.all()
            guard !profiles.isEmpty else {
                print(Term.dim("No profiles found. (Run from the repo root, or set CELLAR_PROFILES_DIR.)"))
                return
            }
            // Grouped by store, because "which client does this need?" is the first thing you
            // want to know about a game and the thing that decides every command that follows.
            let plans = profiles.compactMap { try? Game.plan(slug: $0.slug) }
            for store in GameStore.allCases.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                let inStore = plans.filter { $0.store == store }
                guard !inStore.isEmpty else { continue }
                print(Term.bold(store.descriptor.sectionTitle))
                for plan in inStore {
                    print("  • \(plan.slug.padding(toLength: 26, withPad: " ", startingAt: 0)) "
                        + Term.dim(plan.name))
                }
            }
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print a game profile.")

        @Argument(help: "Profile slug, e.g. 'planet-coaster-2'.")
        var slug: String

        func run() throws {
            guard let ref = ProfileStore.find(slug) else {
                throw CellarError.invalidArgument("No profile '\(slug)'. Try: cellar profiles list")
            }
            let text = (try? String(contentsOf: ref.url, encoding: .utf8)) ?? ""
            print(text)
        }
    }

    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Update the community profile database. [Phase 2]")

        func run() throws {
            print(Term.yellow("Not yet implemented (Phase 2).")
                + " Will sync profiles from the Cellar community registry.")
        }
    }
}
