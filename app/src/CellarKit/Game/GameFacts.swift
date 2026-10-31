import CellarDomain
import Foundation

/// What a profile knows *about* the game, as opposed to how to run it.
///
/// These have always been in the TOML and were never shown to anyone. For a Steam title that was
/// survivable — the store page is a click away. For a Battle.net one there is no page to click, so
/// the profile is the only description of the game the player gets, and `notes` in particular is
/// where Cellar records what has actually been tested and what has not.
public struct GameFacts: Sendable {
    public let developer: String?
    public let released: String?
    public let engine: String?
    public let graphicsAPI: String?
    public let anticheat: String?
    public let drm: String?
    public let online: String?
    public let requiresAccount: String?
    /// `playable` / `untested` / `broken` — how far this profile has actually been verified.
    public let status: String?
    /// Free text: the caveats, the hardware something was tested on, the known patch-day breakage.
    public let notes: String?
    /// `full` / `partial` / `none`: what the profile's author saw a controller do in this game.
    public let controller: String?
    /// `full` / `steering` / `untested` / `none`: what a racing wheel was seen to do in this game.
    public let wheel: String?
    /// Free text: the in-game steps that bind a wheel, for a game made to be driven with one.
    public let wheelSetup: String?

    public init(developer: String? = nil, released: String? = nil, engine: String? = nil,
                graphicsAPI: String? = nil, anticheat: String? = nil, drm: String? = nil,
                online: String? = nil, requiresAccount: String? = nil, status: String? = nil,
                notes: String? = nil, controller: String? = nil, wheel: String? = nil,
                wheelSetup: String? = nil) {
        self.controller = controller
        self.wheel = wheel
        self.wheelSetup = wheelSetup
        self.developer = developer
        self.released = released
        self.engine = engine
        self.graphicsAPI = graphicsAPI
        self.anticheat = anticheat
        self.drm = drm
        self.online = online
        self.requiresAccount = requiresAccount
        self.status = status
        self.notes = notes
    }

    /// The facts worth printing as a spec list, in reading order, skipping what a profile omits.
    public var about: [(label: String, value: String)] {
        [("Developer", developer), ("Released", released),
         ("Engine", engine), ("Graphics", graphicsAPI)]
            .compactMap { label, value in value.map { (label, $0) } }
    }

    /// The facts that answer "will this actually run, and what does it want from me?".
    public var compatibility: [(label: String, value: String)] {
        [("Anti-cheat", anticheat), ("DRM", drm), ("Online", online), ("Account", requiresAccount),
         ("Controller", Controllers.support(controller)), ("Racing wheel", Wheels.support(wheel))]
            .compactMap { label, value in value.map { (label, $0) } }
    }
}
