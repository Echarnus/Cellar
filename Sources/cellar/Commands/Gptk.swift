import ArgumentParser
import CellarKit
import Foundation

struct Gptk: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gptk",
        abstract: "[Advanced] Import Apple's own D3DMetal from a Game Porting Toolkit .dmg.",
        discussion: """
        Most users don't need this: `cellar runner install sikarugir` already provides a Wine build
        with D3DMetal (redistributed by Gcenx under Apple's non-commercial grant). This command is
        for users who prefer to supply Apple's *own* D3DMetal from a .dmg they downloaded from
        https://developer.apple.com/games/game-porting-toolkit/ (free Apple ID). Cellar copies it
        into a local cache only and never redistributes it.
        """,
        subcommands: [Import.self],
        defaultSubcommand: Import.self
    )

    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Import D3DMetal from a GPTK .dmg. [Phase 2]")

        @Argument(help: "Path to the Game Porting Toolkit .dmg.")
        var dmg: String

        func run() throws {
            let path = (dmg as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else {
                throw CellarError.invalidArgument("No file at \(path)")
            }
            print(Term.yellow("Not yet implemented (Phase 2).")
                + " For now, use the bundled D3DMetal: cellar runner install sikarugir")
            print(Term.dim("""
              When implemented, this will mount \(path), copy D3DMetal.framework + libd3dshared.dylib
              into \(Paths.d3dmetalCache.path), then detach. The binaries stay on your machine only.
            """))
        }
    }
}
