import Foundation

/// Every `cellar` command the app issues, as a value rather than a hand-built argument list.
///
/// The app drives the CLI as a subprocess, so the two meet at a command line. Spelling that command
/// line out at each call site (`["saves", "restore", slug, "--backup", id]`) put the contract in
/// string literals on both sides, where a renamed flag only failed when a player pressed the button.
/// Here each command renders its own arguments, and `cellar selftest` parses every one of
/// `CellarCommand.examples` with the CLI's own parser, so a drift fails CI instead.
///
/// The CLI is still the one place a command's behaviour lives; this type only names it.
public enum CellarCommand: Equatable, Sendable {
    // Getting Cellar itself ready, and taking it away again
    case prepare
    case uninstallCellar(keepSaves: Bool)

    // The library
    case refreshLibrary
    case draftProfiles
    case updateProfiles(quiet: Bool)

    // Accounts
    case steamSignIn
    case steamSignOut
    case gogSignIn(code: String)
    case gogSignOut
    case gogStatus
    case battleNetAdd
    case battleNetForget

    // One game
    case setUp(slug: String)
    /// `machineProgress` asks the CLI for the events (`--events`, `CommandEvent`) the app's progress
    /// bar reads.
    case install(slug: String, machineProgress: Bool)
    /// Start a game. The events are always asked for: the launch window follows them.
    case launch(slug: String, showHUD: Bool, backend: GraphicsBackend?)
    case update(slug: String)
    case checkForUpdate(slug: String)
    case uninstall(slug: String, scope: RemovalScope)
    case addToApplications(slug: String)
    case backUpSaves(slug: String)
    case restoreSaves(slug: String, backupID: String)
    case moveToDrive(slug: String, folder: String)
    case moveBack(slug: String)
    case cleanStorage

    // The game's store client
    case steamOpen(slug: String)
    case steamInstall(slug: String)
    case steamAddShortcut(slug: String)
    case battleNetOpen(slug: String)
    case battleNetConfigure(slug: String)
    case gogInstall(slug: String)

    /// The argument list after `cellar`.
    public var arguments: [String] {
        switch self {
        case .prepare: return ["prepare"]
        case .uninstallCellar(let keepSaves):
            return ["uninstall-cellar", "--yes"] + (keepSaves ? [] : ["--no-keep-saves"])

        case .refreshLibrary: return ["library", "--refresh"]
        case .draftProfiles: return ["profiles", "draft", "--all"]
        case .updateProfiles(let quiet): return ["profiles", "update"] + (quiet ? ["--quiet"] : [])

        case .steamSignIn: return ["steam", "login"]
        case .steamSignOut: return ["steam", "login", "--forget"]
        case .gogSignIn(let code): return ["gog", "login", "--code", code]
        case .gogSignOut: return ["gog", "logout"]
        case .gogStatus: return ["gog", "status"]
        case .battleNetAdd: return ["battlenet", "add"]
        case .battleNetForget: return ["battlenet", "forget"]

        case .setUp(let slug): return ["setup", "--profile", slug]
        case .install(let slug, let machineProgress):
            return ["install", slug] + (machineProgress ? ["--events"] : [])
        case .launch(let slug, let showHUD, let backend):
            return ["launch", slug, "--events"]
                + (showHUD ? ["--hud"] : [])
                + (backend.map { ["--backend", $0.rawValue] } ?? [])
        case .update(let slug): return ["update", slug, "--events"]
        case .checkForUpdate(let slug): return ["update", slug, "--check"]
        case .uninstall(let slug, let scope):
            return ["uninstall", slug, "--yes"] + (scope == .bottle ? ["--bottle"] : [])
        case .addToApplications(let slug): return ["app", slug]
        case .backUpSaves(let slug): return ["saves", "backup", slug]
        case .restoreSaves(let slug, let backupID): return ["saves", "restore", slug, "--backup", backupID]
        case .moveToDrive(let slug, let folder): return ["storage", "move", slug, "--to", folder]
        case .moveBack(let slug): return ["storage", "move-back", slug]
        case .cleanStorage: return ["storage", "clean"]

        case .steamOpen(let slug): return ["steam", "open", slug]
        case .steamInstall(let slug): return ["steam", "install", slug]
        case .steamAddShortcut(let slug): return ["steam", "add", slug]
        case .battleNetOpen(let slug): return ["battlenet", "open", slug]
        case .battleNetConfigure(let slug): return ["battlenet", "configure", slug]
        case .gogInstall(let slug): return ["gog", "install", slug]
        }
    }

    /// Whether the CLI prints progress events (`CommandEvent`) for this command, so the runner knows
    /// to read them out of the output rather than show them.
    public var reportsStages: Bool {
        switch self {
        case .install(_, let machineProgress): return machineProgress
        case .launch, .update: return true
        default: return false
        }
    }

    /// The game this command works on, or nil for work that belongs to Cellar as a whole (a
    /// sign-in, the library, the shared runtime). A game's page shows only its own game's work:
    /// Skyrim's page used to say "Launching" while Planet Coaster 2 started.
    public var game: String? {
        switch self {
        case .prepare, .uninstallCellar, .refreshLibrary, .draftProfiles, .updateProfiles,
             .steamSignIn, .steamSignOut, .gogSignIn, .gogSignOut, .gogStatus,
             .battleNetAdd, .battleNetForget, .cleanStorage:
            return nil
        case .setUp(let slug), .install(let slug, _), .launch(let slug, _, _), .update(let slug),
             .checkForUpdate(let slug), .uninstall(let slug, _), .addToApplications(let slug),
             .backUpSaves(let slug), .restoreSaves(let slug, _), .moveToDrive(let slug, _),
             .moveBack(let slug), .steamOpen(let slug), .steamInstall(let slug),
             .steamAddShortcut(let slug), .battleNetOpen(let slug), .battleNetConfigure(let slug),
             .gogInstall(let slug):
            return slug
        }
    }

    /// One of every case, every optional part switched on and off — what `cellar selftest` parses
    /// with the CLI's own parser. Add a new case here too, or nothing checks the CLI accepts it.
    public static let examples: [CellarCommand] = [
        .prepare, .uninstallCellar(keepSaves: true), .uninstallCellar(keepSaves: false),
        .refreshLibrary, .draftProfiles, .updateProfiles(quiet: false), .updateProfiles(quiet: true),
        .steamSignIn, .steamSignOut, .gogSignIn(code: "code"), .gogSignOut, .gogStatus,
        .battleNetAdd, .battleNetForget,
        .setUp(slug: "game"),
        .install(slug: "game", machineProgress: false), .install(slug: "game", machineProgress: true),
        .launch(slug: "game", showHUD: false, backend: nil),
        .launch(slug: "game", showHUD: true, backend: .dxvk),
        .update(slug: "game"), .checkForUpdate(slug: "game"),
        .uninstall(slug: "game", scope: .game), .uninstall(slug: "game", scope: .bottle),
        .addToApplications(slug: "game"), .backUpSaves(slug: "game"),
        .restoreSaves(slug: "game", backupID: "backup"),
        .moveToDrive(slug: "game", folder: "/Volumes/Drive"), .moveBack(slug: "game"), .cleanStorage,
        .steamOpen(slug: "game"), .steamInstall(slug: "game"), .steamAddShortcut(slug: "game"),
        .battleNetOpen(slug: "game"), .battleNetConfigure(slug: "game"), .gogInstall(slug: "game"),
    ]
}
