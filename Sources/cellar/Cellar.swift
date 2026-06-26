import ArgumentParser
import CellarKit

@main
struct Cellar: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cellar",
        abstract: "A free, open, Proton-like layer for running Windows games on macOS (Apple Silicon).",
        discussion: """
        Cellar assembles a Wine runner plus a graphics backend (Apple's D3DMetal, or the
        open-source DXVK/MoltenVK path) into per-game "bottles", driven by a community
        profile database. Planet Coaster 2 is the first supported profile.

        Apple's D3DMetal (Game Porting Toolkit) is proprietary and is never bundled — you
        import it yourself with `cellar gptk import`. Cellar never circumvents DRM and only
        ever works with games you own.

        Run `cellar doctor` first to check your machine.
        """,
        version: "0.0.1 (Phase 0)",
        subcommands: [
            Doctor.self,
            PrefixCommand.self,
            RunnerCommand.self,
            ProfileCommand.self,
            Gptk.self,
            InstallSteam.self,
            Launch.self,
        ],
        defaultSubcommand: Doctor.self
    )
}
