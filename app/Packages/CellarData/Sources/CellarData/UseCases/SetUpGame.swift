import CellarDomain
import Foundation

/// `cellar setup`: runner → bottle → initialised prefix → the store's client.
///
/// Idempotent: safe to re-run; skips steps already done. Holds `SetupLock`, so it waits for a
/// background `cellar prepare` rather than racing it for the same runner directory — and says that
/// it is waiting.
public struct SetUpGame {
    public let plan: GamePlan
    /// The store that stands its client up in the bottle — the plan's own unless a test says otherwise.
    public let adapter: any StoreAdapter

    public init(_ plan: GamePlan, adapter: (any StoreAdapter)? = nil) {
        self.plan = plan
        self.adapter = adapter ?? plan.store.adapter
    }

    @discardableResult
    public func run(_ report: (GameEvent) -> Void = { _ in }) throws -> WineRunner {
        try SetupLock.withLock(waiting: { report(.step($0)) }) {
            try holdingLock(report)
        }
    }

    private func holdingLock(_ report: (GameEvent) -> Void) throws -> WineRunner {
        let plan = plan
        func step(_ message: String) {
            CellarLog.debug(.setup, message, subject: plan.slug)
            report(.step(message))
        }
        func phase(_ progress: InstallProgress) { report(.install(progress)) }

        CellarLog.info(.setup, "Setting up \(plan.name) — store \(plan.store.rawValue), runner "
            + "\(plan.runnerID), backend \(plan.backend), bottle '\(plan.bottleName)'", subject: plan.slug)
        guard SystemEnvironment.isAppleSilicon else {
            throw CellarError.invalidArgument("Cellar requires an Apple Silicon Mac.")
        }
        guard let spec = RunnerCatalog.spec(forID: plan.runnerID) else {
            throw CellarError.invalidArgument("Unknown runner '\(plan.runnerID)'.")
        }
        // Only an x86_64 runner needs Rosetta. Asking it of every runner would lock a native
        // ARM64EC runner out of exactly the Macs it exists for: macOS 28 and later.
        let needsRosetta = RunnerManager.find(id: spec.id)?.needsRosetta ?? spec.architecture.needsRosetta
        if needsRosetta, !SystemEnvironment.rosettaWorks {
            throw CellarError.invalidArgument(SystemEnvironment.rosettaMissingMessage())
        }
        if let why = spec.deprecated {
            step("Warning: runner '\(spec.id)' is deprecated — \(why)")
        }

        if RunnerManager.find(id: spec.id) == nil { phase(InstallProgress(.runtime)) }
        let install = try RunnerManager.install(spec, progress: step)
        let wine = WineRunner(install: install, prefix: plan.prefix, backend: plan.graphicsBackend, metalFX: plan.metalFXUpscaling,
                              language: plan.language.language)

        if !FileManager.default.fileExists(atPath: plan.prefix.appendingPathComponent("system.reg").path) {
            phase(InstallProgress(.bottle))
        }
        if !FileManager.default.fileExists(atPath: plan.prefix.path) {
            step("Creating bottle '\(plan.bottleName)'…")
            try PrefixManager.create(name: plan.bottleName, backend: plan.graphicsBackend, runner: plan.runnerID)
        }

        let registry = plan.prefix.appendingPathComponent("system.reg")
        if !FileManager.default.fileExists(atPath: registry.path) {
            step("Initialising the Wine prefix (64-bit + WoW64)…")
            if !HomeFolderAccess.hasAsked {
                // A pause the player will notice gets announced before it happens. The app asks on
                // first launch instead, so this is the terminal's version of that screen.
                step("macOS may ask to let Cellar use your Documents, Desktop and Downloads folders — that is where Windows games keep their saves.")
            }
            let redirected = try wine.initializePrefix()
            try wine.setWindowsVersion("win10")
            if !redirected.isEmpty {
                let names = redirected.map(\.displayName).joined(separator: ", ")
                report(.step("No access to \(names), so this game's \(redirected.count == 1 ? "folder stays" : "folders stay") inside the bottle. Change it in System Settings → Privacy & Security → Files and Folders."))
            }
            let x86 = plan.prefix.appendingPathComponent("drive_c/Program Files (x86)")
            guard FileManager.default.fileExists(atPath: x86.path) else {
                throw CellarError.ioFailure(
                    "The prefix has no 'Program Files (x86)' — the runner is not a WoW64 build, and the 32-bit store clients can't install into it.")
            }
        } else {
            step("Wine prefix already initialised.")
            wine.updatePrefixIfStale()
        }

        try adapter.setUpClient(plan, wine: wine, step: step, phase: phase)
        // A publisher's launcher the game starts through, after the store's client: Steam's copy of
        // a Rockstar game hands off to the Rockstar Games Launcher (`RockstarLauncher`).
        if let launcher = plan.publisherLauncher {
            if !launcher.isInstalled(in: plan.prefix) { phase(InstallProgress(.client)) }
            try launcher.install(runner: wine, progress: step)
        }
        CellarLog.info(.setup, "Setup finished for \(plan.name).", subject: plan.slug)
        return wine
    }
}
