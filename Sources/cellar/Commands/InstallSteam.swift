import ArgumentParser
import CellarKit

struct InstallSteam: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-steam",
        abstract: "Install the Windows Steam client into a bottle. [Phase 1]",
        discussion: """
        This is the robust, fully-legitimate way to install Windows-only games (like Planet
        Coaster 2) that the macOS Steam client refuses to install: run the real Windows Steam
        client inside the bottle and let it download, validate and update the game normally.
        Nothing here circumvents DRM — Steam's own client handles everything.
        """
    )

    @Argument(help: "Bottle name to install Steam into.")
    var prefix: String

    func run() throws {
        print(Term.yellow("Not yet implemented (Phase 1)."))
        print("  Will download SteamSetup.exe and install Windows Steam into bottle '\(prefix)'.")
    }
}
