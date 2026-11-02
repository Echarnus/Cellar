import Foundation

/// What one verification check found (#203).
///
/// Three answers, never two: a check that could not run is not a pass, and is never shown as one.
/// That is the same honesty rule the app follows for a sign-in it cannot see.
public enum VerificationVerdict: String, Codable, Equatable, Sendable {
    case pass
    case fail
    case couldNotCheck = "could-not-check"

    /// The verdict of several checks together: any failure fails, then any gap is a gap, and only
    /// a set where every check passed passes. No checks at all is a gap, not a pass.
    public static func overall(_ verdicts: [VerificationVerdict]) -> VerificationVerdict {
        if verdicts.contains(.fail) { return .fail }
        if verdicts.isEmpty || verdicts.contains(.couldNotCheck) { return .couldNotCheck }
        return .pass
    }

    /// How the verdict reads in a report, in words a person and a script can both match.
    public var label: String {
        switch self {
        case .pass: return "PASS"
        case .fail: return "FAIL"
        case .couldNotCheck: return "COULD NOT CHECK"
        }
    }
}
