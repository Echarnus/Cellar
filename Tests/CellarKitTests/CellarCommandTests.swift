import CellarDomain
import Testing
@testable import CellarKit

/// The app's side of the command line it shares with the CLI. Whether the CLI *accepts* each of
/// these is checked by `cellar selftest`, which parses `CellarCommand.examples` with the CLI's own
/// parser; this checks the app asks for what it always asked for.
struct CellarCommandTests {

    @Test("Each command renders the argument list the app used to spell out by hand",
          arguments: [
            (CellarCommand.steamSignOut, ["steam", "login", "--forget"]),
            (.gogSignIn(code: "abc"), ["gog", "login", "--code", "abc"]),
            (.uninstallCellar(keepSaves: false), ["uninstall-cellar", "--yes", "--no-keep-saves"]),
            (.uninstallCellar(keepSaves: true), ["uninstall-cellar", "--yes"]),
            (.updateProfiles(quiet: true), ["profiles", "update", "--quiet"]),
            (.install(slug: "witcher-3", machineProgress: true), ["install", "witcher-3", "--events"]),
            (.launch(slug: "diablo-4", showHUD: true, backend: .dxvk),
             ["launch", "diablo-4", "--events", "--hud", "--backend", "dxvk"]),
            (.launch(slug: "diablo-4", showHUD: false, backend: nil), ["launch", "diablo-4", "--events"]),
            (.uninstall(slug: "x", scope: .bottle), ["uninstall", "x", "--yes", "--bottle"]),
            (.uninstall(slug: "x", scope: .game), ["uninstall", "x", "--yes"]),
            (.restoreSaves(slug: "x", backupID: "b1"), ["saves", "restore", "x", "--backup", "b1"]),
            (.moveToDrive(slug: "x", folder: "/Volumes/D"), ["storage", "move", "x", "--to", "/Volumes/D"]),
          ])
    func arguments(_ command: CellarCommand, _ expected: [String]) {
        #expect(command.arguments == expected)
    }

    @Test("Only the commands that print progress markers have them read out of their output")
    func stages() {
        #expect(CellarCommand.launch(slug: "x", showHUD: false, backend: nil).reportsStages)
        #expect(CellarCommand.update(slug: "x").reportsStages)
        #expect(CellarCommand.install(slug: "x", machineProgress: true).reportsStages)
        #expect(!CellarCommand.install(slug: "x", machineProgress: false).reportsStages)
        #expect(!CellarCommand.steamSignIn.reportsStages,
                "a sign-in's output is the player's, every line of it")
    }

    @Test("A credential in a command never reaches the activity log as typed")
    func redactsCode() {
        let shown = Diagnostics.redactCommandLine(CellarCommand.gogSignIn(code: "secret-code").arguments).text
        #expect(!shown.contains("secret-code"))
    }
}
