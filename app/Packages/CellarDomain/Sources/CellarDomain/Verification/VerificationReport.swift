import Foundation

/// Everything one `cellar verify` produced: what was run, on what, and each check's verdict.
///
/// It is the evidence a pull request carries and what "it works" is allowed to mean (#203). The
/// Markdown is for people and pull requests; the JSON is for scripts and the gates.
public struct VerificationReport: Codable, Equatable, Sendable {
    public let slug: String
    public let name: String
    public let store: String
    public let startedAt: Date
    public let finishedAt: Date
    /// What it ran on, so a pass says exactly where it passed.
    public let environment: [String: String]
    public let checks: [VerificationCheck]
    /// Files saved beside the report: screenshots, log excerpts. Relative to the report folder.
    public let attachments: [String]

    public init(slug: String, name: String, store: String, startedAt: Date, finishedAt: Date,
                environment: [String: String], checks: [VerificationCheck], attachments: [String] = []) {
        self.slug = slug
        self.name = name
        self.store = store
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.environment = environment
        self.checks = checks
        self.attachments = attachments
    }

    public var verdict: VerificationVerdict { VerificationVerdict.overall(checks.map(\.verdict)) }

    /// The report as a pull request or an issue shows it.
    public var markdown: String {
        var lines = ["## Verification report: \(name)", "",
                     "**\(verdict.label)**: \(summary)", ""]
        lines.append("| Check | Verdict | What was found |")
        lines.append("|---|---|---|")
        for check in checks {
            lines.append("| \(Self.cell(check.title)) | \(check.verdict.label) | \(Self.cell(check.detail)) |")
        }
        lines.append("")
        lines.append("Ran on " + environment.keys.sorted().map { "\($0) \(environment[$0] ?? "")" }.joined(separator: ", ")
                     + ", from \(Self.timestamp(startedAt)) to \(Self.timestamp(finishedAt)).")
        let withEvidence = checks.filter { $0.verdict != .pass && !$0.evidence.isEmpty }
        if !withEvidence.isEmpty {
            lines += ["", "### Evidence"]
            for check in withEvidence {
                lines += ["", "**\(check.title)** (`\(check.id)`)", "", "```"]
                lines += check.evidence.prefix(40)
                lines.append("```")
            }
        }
        if !attachments.isEmpty {
            lines += ["", "Saved beside this report: " + attachments.map { "`\($0)`" }.joined(separator: ", ")]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One sentence: how many checks passed, failed and could not run.
    public var summary: String {
        let passed = checks.filter { $0.verdict == .pass }.count
        let failed = checks.filter { $0.verdict == .fail }.count
        let gaps = checks.filter { $0.verdict == .couldNotCheck }.count
        var parts = ["\(passed) of \(checks.count) checks passed"]
        if failed > 0 { parts.append("\(failed) failed") }
        if gaps > 0 { parts.append("\(gaps) could not be checked") }
        return parts.joined(separator: ", ") + "."
    }

    static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
