import CellarDomain
import Foundation

/// The compatibility facts read through the engine's own wording for controllers and wheels.
extension GameFacts {
    /// The facts that answer "will this actually run, and what does it want from me?".
    public var compatibility: [(label: String, value: String)] {
        [("Anti-cheat", anticheat), ("DRM", drm), ("Online", online), ("Account", requiresAccount),
         ("Controller", Controllers.support(controller)), ("Racing wheel", Wheels.support(wheel))]
            .compactMap { label, value in value.map { (label, $0) } }
    }
}
