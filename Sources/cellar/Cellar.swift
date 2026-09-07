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
        Planet Coaster 2 is the first supported profile.

        Quick start:
          cellar doctor                 check your machine
          cellar setup                  install runner + bottle + Windows Steam (Planet Coaster 2)
          cellar steam open  planet-coaster-2   log in, install the game
          cellar launch      planet-coaster-2   play

        Cellar never bundles Apple's proprietary D3DMetal in its own releases, never circumvents
        DRM, and only ever works with games you own.
        """,
        version: "0.1.0 (Phase 1)",
        subcommands: [
            Doctor.self,
            Setup.self,
            SteamCommand.self,
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
