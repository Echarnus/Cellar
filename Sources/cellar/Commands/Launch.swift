import ArgumentParser
import CellarKit
import Foundation

struct Launch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch a game. Runs the exe directly when the game allows it, else through its store's client (Steam or Battle.net)."
    )

    @Argument(help: "Profile slug to launch, e.g. 'diablo-4'.")
    var slug: String

    @Flag(help: "Show the Metal performance HUD (FPS / frametime).")
    var hud = false

    @Flag(name: .customLong("store"), help: "Force the store-client launch path even if a direct launch is possible.")
    var forceStore = false

    @Flag(name: .customLong("no-wait"), help: "Return immediately after launch instead of waiting for the game to exit and closing the layer.")
    var noWait = false

    @Flag(name: .customLong("print-env"), help: "Print the environment the game would get and exit (debugging).")
    var printEnv = false

    @Flag(name: .customLong("machine-progress"),
          help: "Also print a marker line each time the launch reaches a new step, for the Cellar app's launch window.")
    var machineProgress = false

    /// Announce a step. Prose stays as it is for whoever is reading the terminal; the marker is an
    /// extra line the app parses and hides, so neither audience is served a compromise.
    private func report(_ stage: LaunchStage) {
        guard machineProgress else { return }
        print(LaunchMarker.line(stage))
    }

    func run() throws {
        let plan = try Game.plan(slug: slug)

        if printEnv {
            guard let wine = Game.wineRunner(plan) else {
                throw CellarError.invalidArgument(
                    "Runner '\(plan.runnerID)' isn't installed. Run: cellar setup --profile \(slug)")
            }
            var extra = WineRunner.d3dMetalEnv(showHUD: hud)
            for (key, value) in plan.env { extra[key] = value }
            for (key, value) in wine.environment(extra: extra).sorted(by: { $0.key < $1.key }) {
                print("\(key)=\(value)")
            }
            return
        }

        // A store that can tell us nobody is signed in should say so before a launch that will
        // stall on a login screen. Battle.net can't tell, so it doesn't pretend to — and a store
        // Cellar signs into itself has no client to open, so it gets its own instruction.
        if plan.store.descriptor.canDetectSignIn, Game.storeClientInstalled(plan),
           Game.signedInAccount(plan) == nil {
            switch plan.store.descriptor.authStyle {
            case .cellarHeldToken:
                // Only worth saying when the game isn't on disk: a DRM-free game already installed
                // runs perfectly well signed out, so warning about it would be a lie.
                if plan.directLaunchExe == nil {
                    print(Term.yellow("Not signed in to \(plan.store.displayName) yet.")
                        + " Run: cellar \(plan.store.rawValue) login  and sign in first.")
                }
            case .inClientWindow, .none:
                print(Term.yellow("Nobody is signed in to this bottle's \(plan.store.displayName) yet.")
                    + " Run: cellar \(plan.store.rawValue) open \(slug)  and sign in first.")
            }
        }

        let route = try Game.launch(plan, showHUD: hud, forceStore: forceStore, stage: report) {
            print("  " + Term.dim($0))
        }
        print(Term.green("\(plan.name) is up."))

        guard !noWait else { return }
        switch route {
        case .direct:
            print(Term.dim("Playing… (Cellar will close the layer when you quit the game)"))
        case .steam, .battlenet:
            print(Term.dim("Playing… (Cellar will close \(plan.store.displayName) when you quit the game)"))
        }
        report(.playing)
        Game.waitForExitThenShutDown(plan, route: route)
        report(.closed)
        print(Term.green("\(plan.name) closed. Layer shut down."))
    }
}
