import CellarDomain
import ArgumentParser
import CellarKit
import Foundation

struct ProfileCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "profiles",
        abstract: "Browse the per-game profile database.",
        subcommands: [List.self, Show.self, Draft.self, Update.self, Version.self]
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

    struct Draft: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Write a profile for an installed game that has none, from its own files.",
            discussion: """
            Cellar finds the game's exe, reads its architecture and graphics API from the PE header,
            and picks the backend that suits that API. Every value is a guess and the profile says
            so: it is marked untested, and the app lists it under "Cellar guessed these settings".

              cellar profiles draft                 list installed games with no profile
              cellar profiles draft 1145360         write one (a Steam app id)
              cellar profiles draft --all           write one for each of them
            """)

        @Argument(help: "Steam app id of the game to draft a profile for.")
        var appID: Int?

        @Flag(name: .long, help: "Draft a profile for every installed game that has none.")
        var all = false

        func run() throws {
            let candidates = DraftProfile.candidates()
            if let appID {
                guard let candidate = candidates.first(where: { $0.steamAppID == appID }) else {
                    throw CellarError.invalidArgument(
                        "No installed Steam game \(appID) without a profile. See which there are: cellar profiles draft")
                }
                let slug = try DraftProfile.write(candidate)
                print(Term.green("Drafted: ") + "\(candidate.name) → \(slug)" + Term.dim("  (cellar profiles show \(slug))"))
                return
            }
            guard !candidates.isEmpty else {
                print("Every installed game already has a profile.")
                return
            }
            guard all else {
                print("Installed games with no profile:")
                for candidate in candidates {
                    print("  • \(candidate.name)" + Term.dim("  (Steam \(candidate.steamAppID.map(String.init) ?? "?"))"))
                }
                print(Term.dim("Draft one: cellar profiles draft <app id>   ·   all of them: cellar profiles draft --all"))
                return
            }
            var failed = 0
            for candidate in candidates {
                do {
                    let slug = try DraftProfile.write(candidate)
                    print(Term.green("Drafted: ") + "\(candidate.name) → \(slug)")
                } catch {
                    failed += 1
                    print(Term.yellow("Skipped: ") + CellarLog.describe(error))
                }
            }
            if failed > 0 { throw ExitCode(1) }
        }
    }

    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Fetch the latest game database from Cellar's releases, signature checked.",
            discussion: """
            New and fixed game profiles are published with every release as one signed file. This
            fetches it, refuses it unless Cellar's key signed it, and keeps it beside your own
            profiles, which still win. Offline, or on any failure, the database you have stays.
            """)

        @Flag(name: .long, help: "Print only failures — for the app's quiet daily check.")
        var quiet = false

        func run() throws {
            do {
                let installed = try ProfileUpdates.update()
                guard !quiet else { return }
                print(Term.green("Game database updated: ") + "\(installed.count) profiles, published with Cellar \(installed.cellarVersion) "
                    + Term.dim("(\(installed.published.formatted(date: .abbreviated, time: .omitted)))"))
            } catch let failure as ProfileUpdates.Failure {
                if quiet, failure == .noKey { return }
                throw CellarError.ioFailure(failure.description)
            }
        }
    }

    struct Version: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show which game database is in use.")

        func run() throws {
            if let installed = ProfileUpdates.installed {
                print("Downloaded: \(installed.count) profiles, published with Cellar \(installed.cellarVersion), "
                    + "fetched \(installed.fetched.formatted(date: .abbreviated, time: .shortened))")
            } else {
                print("The one that shipped with Cellar \(CellarVersion.current).")
            }
            print(Term.dim("\(ProfileStore.all().count) profiles in use, your own included. Update: cellar profiles update"))
        }
    }
}
