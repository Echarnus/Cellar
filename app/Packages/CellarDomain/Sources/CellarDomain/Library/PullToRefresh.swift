/// **Pull the library down to ask the stores again** (Kenneth, 2026-11-06: "No refresh button.
/// Drag to refresh.").
///
/// The sidebar reports how far it is pulled past its top (the elastic overscroll a trackpad gives),
/// and this decides when that is a request: once per pull, when it passes `threshold`. Firing at the
/// threshold rather than on release is how a pull-to-refresh behaves on the iPhone, and it can't
/// fire twice for one gesture: it re-arms only after the list is back at rest.
public struct PullToRefresh: Sendable, Equatable {
    /// Points past the top that make a pull a request. Far enough that ordinary scrolling past the
    /// top of a short list, which bounces a few points, never counts.
    public static let threshold: Double = 64

    /// How far the list is pulled now, 0 at rest.
    public private(set) var distance: Double = 0
    private var fired = false

    public init() {}

    /// How far the pull has gone toward a request, 0…1, for the indicator.
    public var progress: Double { min(1, distance / Self.threshold) }

    /// Take the latest overscroll; true exactly once per pull, when it crosses the threshold.
    public mutating func update(overscroll: Double) -> Bool {
        distance = max(0, overscroll)
        if distance <= 0.5 { fired = false; return false }
        guard !fired, distance >= Self.threshold else { return false }
        fired = true
        return true
    }
}
