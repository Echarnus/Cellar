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
          cellar setup --profile planet-coaster-2   runner + bottle + Windows Steam
          cellar steam open  planet-coaster-2    sign in once (shared by every Steam game)
          cellar launch      planet-coaster-2    play

        Quick start — GOG (DRM-free, no client in the bottle):
          cellar gog login                       sign in once, for your whole library
          cellar gog library                     see what you own
          cellar gog install witcher-3           download + install
          cellar launch witcher-3                play

        Quick start — Battle.net:
          cellar setup --profile diablo-4        runner + bottle + Battle.net
          cellar battlenet open diablo-4         sign in, install Diablo IV from the client
          cellar launch diablo-4                 play

        When something goes wrong:
          cellar logs                            what Cellar just did, and where it failed
          cellar logs export                     one text file to attach to a bug report

        Cellar never bundles Apple's proprietary D3DMetal in its own releases, never circumvents
        DRM, and only ever works with games you own.
        """,
        version: CellarVersion.current,
        subcommands: [
            Doctor.self,
            Setup.self,
            SteamCommand.self,
            BattleNetCommand.self,
            GogCommand.self,
            Accounts.self,
            FetchDepot.self,
            Launch.self,
            RunnerCommand.self,
            PrefixCommand.self,
            ProfileCommand.self,
            Gptk.self,
            SelfTest.self,
            LogsCommand.self,
        ],
        defaultSubcommand: Doctor.self
    )

    /// Stand in for ArgumentParser's generated entry point so every invocation — and, more to the
    /// point, every failure — lands in the rolling log. The app drives this CLI for its actions, so
    /// this one place covers both front-ends.
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        // Reading the log must not write to it.
        let quiet = arguments.first == "logs"
        let redacted = Diagnostics.redactCommandLine(arguments)
        if !quiet { CellarLog.debug(.app, "cellar " + redacted.text) }

        do {
            var command = try parseAsRoot(arguments)
            try command.run()
        } catch {
            // `--help` and `--version` exit through this path too; they are not failures.
            if !quiet, exitCode(for: error) != ExitCode.success {
                CellarLog.error(category(for: arguments.first),
                                failureLine(redacted, message(for: error)))
            }
            exit(withError: error)
        }
    }

    /// Compose the line a failure is logged as. Separate from `main` so the self-test can drive it
    /// with a *real* parse error: the reason text is generated from the same argv the invocation
    /// came from, so it has to be scrubbed with the same secrets, or the redaction on the left of
    /// the line is undone by the quote on the right of it.
    static func failureLine(_ redacted: Diagnostics.RedactedCommandLine, _ reason: String) -> String {
        "cellar \(redacted.text) failed: \(redacted.scrub(reason))"
    }

    /// File a failure under the part of Cellar the player was actually using.
    private static func category(for subcommand: String?) -> LogCategory {
        switch subcommand {
        case "launch":                      return .launch
        case "setup":                       return .setup
        case "fetch-depot":                 return .install
        case "steam", "battlenet", "gog":   return .store
        case "accounts":                    return .account
        case "runner":                      return .runner
        case "prefix":                      return .prefix
        default:                            return .app
        }
    }
}
