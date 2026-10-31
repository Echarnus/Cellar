import CellarDomain
import Foundation

/// The outside world, as one value a piece of CellarKit is handed instead of reaching for it.
///
/// CellarKit grew as namespaces of `static func`s that read `Paths` (and through it the process-wide
/// `CELLAR_HOME`) and the clock wherever they needed them. That works, but a test can only move the
/// whole process to another home, so two tests cannot have two homes at once, and nothing can say
/// "it is now 09:00" without a parameter threaded by hand. An environment is passed in, so each
/// caller — a test, the CLI, the app — decides what "home" and "now" are.
///
/// It grows one slice at a time (docs/APP-ARCHITECTURE.md → Target: the engine). Save backups were
/// the first; a port joins it when the slice that needs it moves, not before. `.live` is what every
/// unconverted call site gets, so nothing has to move at once.
public struct CellarEnvironment: Sendable {
    /// The root of everything Cellar owns on disk — what `Paths.appSupport` is for `.live`.
    public var home: URL
    /// The clock.
    public var now: @Sendable () -> Date

    public init(home: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.home = home
        self.now = now
    }

    /// The player's real Cellar: `Paths.appSupport` (with `CELLAR_HOME` honoured) and the real clock.
    public static var live: CellarEnvironment { CellarEnvironment(home: Paths.appSupport) }

    /// Copies of each bottle's save games (`SaveBackups`). Beside the bottles, never inside one, so
    /// removing a bottle cannot take its backups with it.
    public var saveBackups: URL { home.appendingPathComponent("save-backups", isDirectory: true) }
}
