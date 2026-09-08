import ArgumentParser
import CellarKit

struct FetchDepot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fetch-depot",
        abstract: "Download an owned game's Windows files directly via DepotDownloader — no Windows Steam client.",
        discussion: """
        The Proton-like download path: authenticate with your Steam account (Steam Guard/2FA is
        prompted here) and pull the game's Windows depot straight into the bottle. Whether the game
        then needs Steam *running* to play is a per-title DRM question — Cellar's `launch` picks the
        Steam-free path automatically when the profile allows it (needs_live_steam = false).
        """
    )

    @Argument(help: "Profile slug, e.g. 'age-of-empires-2-de'.")
    var slug: String

    @Option(name: .shortAndLong, help: "Steam account name to download with.")
    var username: String

    func run() throws {
        let plan = try Game.plan(slug: slug)
        print(Term.bold("Fetching \(plan.name)") + Term.dim("  (Steam auth as \(username); 2FA will prompt below)"))
        try Game.fetchDepot(plan, username: username) { print("  " + Term.dim($0)) }
        if plan.needsLiveSession {
            print(Term.yellow("Note: \(plan.name) needs a live \(plan.store.displayName) session to play")
                + " — `cellar launch \(slug)` will use the silent-client path.")
        } else {
            print(Term.green("Ready.") + " Play with: cellar launch \(slug)  (no Steam needed)")
        }
    }
}
