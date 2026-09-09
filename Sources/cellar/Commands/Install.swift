import ArgumentParser
import CellarKit

/// One verb for "get this game onto my Mac", whatever store it came from.
///
/// It used to be four — `steam install`, `gog install`, `battlenet install`, `fetch-depot` — and
/// which one applied was a fact about Cellar's plumbing, not about the player's game. The store
/// still decides *how* (that difference is real), but it no longer decides what to type.
struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install a game you own — Cellar picks the right route for its store.",
        discussion: """
        Steam       downloaded straight from your Steam library with the sign-in you gave once,
                    with no Steam window to click through. `cellar steam login` if you haven't.
        GOG         downloaded and installed from your GOG library. DRM-free, no client.
        Battle.net  opens Blizzard's client, because Battle.net publishes no way to install a
                    product from outside it. Cellar takes over once the files are down.
        """)

    @Argument(help: "Profile slug (see: cellar library).") var slug: String

    @Flag(help: "Install even if Cellar hasn't confirmed you own it.")
    var force = false

    func run() throws {
        let plan = try Game.plan(slug: slug)
        // Who answers for this game — not always the store it is filed under. A DRM-free game
        // bought on Steam has no client and is still Steam's to confirm.
        let gate = StoreLibrary.gatingStore(for: plan)

        // Every check that can refuse this install happens *before* the first byte is downloaded.
        // Setting a bottle up fetches a Wine runner — gigabytes — so discovering the sign-in is
        // missing afterwards spends somebody's bandwidth to tell them something Cellar knew from
        // the start.
        if !force {
            if gate == .steam, !SteamAccount.isSignedIn {
                throw CellarError.invalidArgument(
                    "\(SteamAccount.state.summary) Cellar needs it to know this game is yours, and to download it: cellar steam login")
            }
            switch StoreLibrary.ownership(of: plan) {
            case .notOwned:
                throw CellarError.invalidArgument(
                    "\(plan.name) isn't in your \(gate.displayName) library. Cellar only installs games you own.")
            case .unknown(let why) where gate.canAnswerOwnership:
                print(Term.yellow("Can't confirm you own this: ") + why)
                print(Term.dim("  Checking now — this is the same question the install would ask."))
                try StoreLibrary.refreshSteamIfSteam(plan)
                if case .notOwned = StoreLibrary.ownership(of: plan) {
                    throw CellarError.invalidArgument(
                        "\(plan.name) isn't in your \(gate.displayName) library. Cellar only installs games you own.")
                }
            default:
                break
            }
        }

        print(Term.bold("Installing \(plan.name)") + Term.dim("  (\(plan.store.displayName))"))
        try Game.setUp(plan) { print("  " + Term.dim($0)) }
        try Game.installGame(plan) { print("  " + Term.dim($0)) }
        if Game.isGameInstalled(plan) {
            print(Term.green("Installed.") + " Play it with: cellar launch \(slug)")
        } else {
            // Battle.net's route ends with a window the player still has to use — saying "installed"
            // here would be a claim about something Cellar did not do.
            print(Term.yellow("Not finished yet.")
                + " Finish the install in the client, then: cellar launch \(slug)")
        }
    }
}

extension StoreLibrary {
    /// Re-ask the one store that answers per game, when a single game's answer is missing.
    static func refreshSteamIfSteam(_ plan: GamePlan) throws {
        guard gatingStore(for: plan) == .steam, plan.appID != nil else { return }
        try refreshSteam()
    }
}
