import Foundation

/// One check of a verification run: what was asked, what was found, and the evidence for it.
public struct VerificationCheck: Codable, Equatable, Sendable {
    /// A stable identifier a script can match, e.g. `steam-signed-in` or `run-2.survive`.
    public let id: String
    /// The question, in a sentence: "Steam is signed in, with no sign-in prompt".
    public let title: String
    public let verdict: VerificationVerdict
    /// What was found, in a sentence. Always says why for a failure or a gap.
    public let detail: String
    /// The lines that back the verdict: log lines, process command lines, addresses. Scrubbed of
    /// credentials by whoever collects them.
    public let evidence: [String]

    public init(id: String, title: String, verdict: VerificationVerdict, detail: String, evidence: [String] = []) {
        self.id = id
        self.title = title
        self.verdict = verdict
        self.detail = detail
        self.evidence = evidence
    }

    /// The same check, numbered for one launch of several (`run-2.survive`).
    public func inRun(_ run: Int) -> VerificationCheck {
        VerificationCheck(id: "run-\(run).\(id)", title: title, verdict: verdict, detail: detail, evidence: evidence)
    }
}
