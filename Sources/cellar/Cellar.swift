import ArgumentParser
import CellarKit

@main
struct Cellar: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cellar",
        abstract: "A free, open, Proton-like layer for running Windows games on macOS (Apple Silicon).",
        discussion: """
        Cellar assembles a Wine runner plus a graphics backend (Apple's D3DMetal, or the
        open-source DXVK/MoltenVK path) into per-game "bottles", driven by a profile database.
        Each game names the store it comes from, and Cellar stands that store's client up inside
        the bottle: Windows Steam, or Blizzard's Battle.net.

        Quick start — Steam:
          cellar doctor                          check your machine
          cellar setup --profile planet-coaster-2   runner + bottle + Windows Steam
          cellar steam open  planet-coaster-2    sign in, install the game
          cellar launch      planet-coaster-2    play

        Quick start — Battle.net:
          cellar setup --profile diablo-4        runner + bottle + Battle.net
          cellar battlenet open diablo-4         sign in, install Diablo IV from the client
          cellar launch diablo-4                 play

        Cellar never bundles Apple's proprietary D3DMetal in its own releases, never circumvents
        DRM, and only ever works with games you own.
        """,
        version: "0.2.0",
        subcommands: [
            Doctor.self,
            Setup.self,
            SteamCommand.self,
            BattleNetCommand.self,
            FetchDepot.self,
            Launch.self,
            RunnerCommand.self,
            PrefixCommand.self,
            ProfileCommand.self,
            Gptk.self,
            SelfTest.self,
        ],
        defaultSubcommand: Doctor.self
    )
}
