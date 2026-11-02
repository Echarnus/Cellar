import CellarDomain
import ArgumentParser
import CellarData
import Foundation

struct Launch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch a game. Runs the exe directly when the game allows it, else through its store's client."
    )

    @Argument(help: "Profile slug to launch, e.g. 'diablo-4'.")
    var slug: String

    @Flag(help: "Show the Metal performance HUD (FPS / frametime) this once. To keep it on: cellar perf set <slug> metal_hud on")
    var hud = false

    @Flag(name: .customLong("store"), help: "Force the store-client launch path even if a direct launch is possible.")
    var forceStore = false

    @Flag(name: .customLong("no-update"),
          help: "Start the version on disk without asking Steam for a newer one first (games Cellar downloaded itself).")
    var noUpdate = false

    @Option(name: .long,
            help: "Use this graphics backend (d3dmetal, dxvk, dxmt, vkd3d, wined3d). If the game comes up, Cellar keeps using it for this game.")
    var backend: String?

    @Flag(name: .customLong("no-wait"), help: "Return immediately after launch instead of waiting for the game to exit and closing the layer.")
    var noWait = false

    @Flag(name: .customLong("print-env"), help: "Print the environment the game would get and exit (debugging).")
    var printEnv = false

    @Flag(name: .customLong("machine-progress"),
          help: "Also print a marker line each time the launch reaches a new step, for the Cellar app's launch window. Superseded by --events.")
    var machineProgress = false

    @Flag(name: .customLong("events"),
          help: "Also print each progress step as a versioned JSON line, for the Cellar app.")
    var events = false

    private var output: EventOutput { EventOutput(json: events, markers: machineProgress) }

    /// Announce a step. Prose stays as it is for whoever is reading the terminal; the marker is an
    /// extra line the app parses and hides, so neither audience is served a compromise.
    private func report(_ stage: LaunchStage) {
        output.emit(.stage(stage))
    }

    /// Work a launch has to do before the game can start — Steam's first update — reported the way
    /// `install` reports its phases, so the launch window can draw the same bar.
    private func updateReporter() -> (InstallProgress) -> Void {
        var last: InstallProgress?
        let sink = self.output
        return { progress in
            guard sink.isOn else { return }
            if let was = last?.fraction, let now = progress.fraction, last?.phase == progress.phase,
               abs(now - was) < 0.001 { return }
            last = progress
            sink.emit(.install(progress))
        }
    }

    func run() throws {
        var plan = try Game.plan(slug: slug)
        let chosenBackend = try backend.map(BackendCommand.backend)
        if let chosenBackend { plan.backend = chosenBackend.rawValue }

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
            case .inClientWindow:
                // Only when Cellar can't sign that client in with the session it already holds —
                // otherwise this promised a window that never opens.
                if plan.needsLiveSession,
                   !SteamBottle.clientSessionReadiness(in: plan.prefix).signsInByItself {
                    print(Term.yellow("\(plan.store.displayName)'s window opens first so you can sign in to it.")
                        + " \(plan.name) starts once you're in — once, for every \(plan.store.displayName) game.")
                }
            }
        }

        // The app reads this command's output through a pipe, and the app can go away mid-session:
        // closing its last window quits it. The next line printed would then end this process on
        // SIGPIPE — and with it the only thing waiting to close the layer, so every Wine process of
        // the game outlived it. Losing the reader costs the output, never the shutdown.
        signal(SIGPIPE, SIG_IGN)

        // Whether the game itself was started. Only then is a different backend worth suggesting:
        // a runner that isn't installed or a game that isn't downloaded is not a graphics problem.
        var started = false
        let launch = LaunchGame(plan, showHUD: hud, forceStore: forceStore, checkUpdates: !noUpdate)
        let route: LaunchRoute
        do {
            let update = updateReporter()
            route = try launch.run { event in
                event.deliver(progress: { print("  " + Term.dim($0)) },
                              install: update,
                              launch: { stage in
                                  if stage == .starting { started = true }
                                  report(stage)
                              })
            }
        } catch {
            if started, let retry = plan.retryBackend {
                print(Term.yellow("\(plan.name) didn't come up on \(plan.graphicsBackend.displayName).")
                    + " Its profile names \(retry.displayName) to try next: cellar launch \(slug) --backend \(retry.rawValue)")
            }
            throw error
        }
        print(Term.green("\(plan.name) is up."))

        // A backend the player asked for and that brought the game up is the one to keep.
        if let chosenBackend {
            BackendCommand.remember(chosenBackend, for: plan)
        }

        guard !noWait else { return }
        switch route {
        case .direct:
            print(Term.dim("Playing… (Cellar will close the layer when you quit the game)"))
        case .steam, .steamAlongside, .battlenet:
            print(Term.dim("Playing… (Cellar will close \(plan.store.displayName) when you quit the game)"))
        }
        report(.playing)
        launch.waitForExitThenShutDown(route) { report(.closing) }
        report(.closed)
        print(Term.green("\(plan.name) closed. Layer shut down."))
    }
}
