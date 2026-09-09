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
        Each game names the store it comes from, and that decides how it is set up: Windows Steam or
        Blizzard's Battle.net stood up inside the bottle, or — for GOG — no client at all, just an
        OAuth token and a DRM-free installer. `cellar accounts` shows where you're signed in.

        Quick start — Steam:
          cellar doctor                          check your machine
          cellar steam login                     one QR scan, and that is the last of it
          cellar library                         the games you own that Cellar can run
          cellar install planet-coaster-2        downloaded with that sign-in, no Steam window
          cellar launch  planet-coaster-2        play

        Quick start — GOG (DRM-free, no client in the bottle):
          cellar gog login                       sign in once, for your whole library
          cellar gog library                     see what you own
          cellar gog install witcher-3           download + install
          cellar launch witcher-3                play

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
            LibraryCommand.self,
            Install.self,
            SteamCommand.self,
            BattleNetCommand.self,
            GogCommand.self,
            Accounts.self,
            Launch.self,
            RunnerCommand.self,
            PrefixCommand.self,
            ProfileCommand.self,
            Gptk.self,
            SelfTest.self,
            ResetCommand.self,
        ],
        defaultSubcommand: Doctor.self
    )
}
