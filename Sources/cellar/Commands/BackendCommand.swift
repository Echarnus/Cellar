import ArgumentParser
import CellarKit
import Foundation

struct BackendCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backend",
        abstract: "Show or change the graphics backend a game runs on.",
        discussion: """
        Every profile names the backend the game was tested on and one to fall back to. Switching
        is kept in the game's bottle, so a profile update never undoes it.

          cellar backend planet-coaster-2           which backend it uses, and whose choice that is
          cellar backend planet-coaster-2 dxvk      use DXVK from the next launch on
          cellar backend planet-coaster-2 --reset   back to the profile's backend
        """
    )

    @Argument(help: "Profile slug, e.g. 'planet-coaster-2'.")
    var slug: String

    @Argument(help: "Backend to use: d3dmetal, dxvk, dxmt, vkd3d or wined3d.")
    var backend: String?

    @Flag(name: .long, help: "Forget the choice and use the profile's backend again.")
    var reset = false

    static func backend(_ text: String) throws -> GraphicsBackend {
        guard let backend = GraphicsBackend(named: text) else {
            let known = GraphicsBackend.allCases.map(\.rawValue).joined(separator: ", ")
            throw CellarError.invalidArgument("'\(text)' isn't a graphics backend Cellar knows. Use one of: \(known)")
        }
        return backend
    }

    /// Keep `backend` as this game's choice, or forget the choice when it is the profile's own.
    /// Best effort: the game is already running on it, so a file that can't be written is said,
    /// not thrown.
    static func remember(_ backend: GraphicsBackend, for plan: GamePlan) {
        let file = BottleConfig.url(forBottle: plan.bottleName)
        let isProfiles = backend.rawValue == plan.profileBackend
        do {
            try BackendChoice.set(isProfiles ? nil : backend, in: file)
            if !isProfiles {
                print(Term.dim("\(plan.name) keeps using \(backend.displayName) from now on. Back to the profile's: cellar backend \(plan.slug) --reset"))
            }
        } catch {
            print(Term.yellow("Couldn't remember \(backend.displayName) for \(plan.name): \(CellarLog.describe(error))"))
        }
    }

    func run() throws {
        let plan = try Game.plan(slug: slug)
        if reset || backend != nil {
            guard FileManager.default.fileExists(atPath: plan.prefix.path) else {
                throw CellarError.invalidArgument(
                    "\(plan.name) has no bottle yet to keep this in. Run: cellar setup --profile \(plan.slug)  first.")
            }
        }
        let file = BottleConfig.url(forBottle: plan.bottleName)
        let profiles = GraphicsBackend(rawValue: plan.profileBackend)?.displayName ?? plan.profileBackend
        if reset {
            try BackendChoice.set(nil, in: file)
            print("\(plan.name) uses its profile's backend again: " + Term.bold(profiles))
            return
        }
        if let backend {
            let chosen = try Self.backend(backend)
            try BackendChoice.set(chosen.rawValue == plan.profileBackend ? nil : chosen, in: file)
            print("\(plan.name) uses " + Term.bold(chosen.displayName) + " from its next launch.")
            return
        }
        let current = plan.graphicsBackend.displayName
        print("\(plan.name): " + Term.bold(current)
            + Term.dim(plan.backend == plan.profileBackend ? "  (the profile's)" : "  (your choice; the profile's is \(profiles))"))
        if let fallback = plan.fallbackBackend.flatMap(GraphicsBackend.init(rawValue:)), fallback.rawValue != plan.backend {
            print(Term.dim("Fallback named by the profile: \(fallback.displayName). Try it: cellar launch \(plan.slug) --backend \(fallback.rawValue)"))
        }
    }
}
