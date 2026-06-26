import ArgumentParser
import CellarKit
import Foundation

struct Gptk: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gptk",
        abstract: "Import Apple's D3DMetal (Game Porting Toolkit) from a .dmg you downloaded.",
        discussion: """
        Apple's D3DMetal is proprietary and licensed for personal/non-commercial use; Cellar
        never bundles or redistributes it. Download the Game Porting Toolkit .dmg from
        https://developer.apple.com/games/game-porting-toolkit/ (free Apple ID), then point
        this command at it. Cellar copies the framework into its local cache only.
        """,
        subcommands: [Import.self],
        defaultSubcommand: Import.self
    )

    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Import D3DMetal from a GPTK .dmg. [Phase 1]")

        @Argument(help: "Path to the Game Porting Toolkit .dmg.")
        var dmg: String

        func run() throws {
            let path = (dmg as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else {
                throw CellarError.invalidArgument("No file at \(path)")
            }
            print(Term.yellow("Not yet implemented (Phase 1)."))
            print("""
              Will mount \(path), copy D3DMetal.framework + libd3dshared.dylib into
              \(Paths.d3dmetalCache.path), then detach the image. The binaries stay on your
              machine only and are never committed or uploaded.
            """)
        }
    }
}
