import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// A player's compatibility report: built by Cellar, read by the player, filed by the player — and
/// carrying nothing that identifies them.
@Suite(.serialized)
struct CompatibilityReportTests {

    private func facts(notes: String? = nil, outcome: CompatibilityReport.Outcome = .issues) -> CompatibilityReport.Facts {
        CompatibilityReport.Facts(game: "Fixture", slug: "fixture", store: "Steam", runner: "wineforge",
                                  backend: "d3dmetal", profileStatus: "untested", macOS: "26.1.0",
                                  chip: "Apple M3 Pro", cellarVersion: "0.2.0", outcome: outcome, notes: notes)
    }

    /// Every string the report could put in front of GitHub.
    private func everything(_ facts: CompatibilityReport.Facts) -> String {
        [CompatibilityReport.title(facts), CompatibilityReport.environment(facts),
         CompatibilityReport.details(facts), CompatibilityReport.issueURL(facts).absoluteString.removingPercentEncoding ?? ""]
            .joined(separator: "\n")
    }

    @Test("No account name, home path or token reaches the report")
    func redaction() {
        let saved = CompatibilityReport.knownAccountNames
        CompatibilityReport.knownAccountNames = ["gaben_fan_42"]
        defer { CompatibilityReport.knownAccountNames = saved }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let notes = """
        Crashed loading \(home)/Library/Application Support/Cellar/prefixes/x/save.dat
        Steam showed Gaben_Fan_42 as signed in. refresh_token=eyJhbGciOi.secret.value
        """
        let text = everything(facts(notes: notes))
        #expect(!text.contains(home))
        #expect(!text.lowercased().contains("gaben_fan_42"))
        #expect(!text.contains("eyJhbGciOi"))
        if NSUserName().count >= 3 { #expect(!text.contains(NSUserName())) }
        #expect(text.contains("Crashed loading ~/Library"), "the useful part of the note survives")
    }

    @Test("The form link prefills the issue form's own fields and asks for its label")
    func issueURL() throws {
        let url = CompatibilityReport.issueURL(facts(outcome: .works))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(url.absoluteString.hasPrefix("https://github.com/Echarnus/Cellar/issues/new?"))
        #expect(value("template") == "compatibility-report.yml")
        #expect(value("labels") == CompatibilityReport.label)
        #expect(value("outcome") == "Works")
        #expect(value("game") == "Fixture (fixture)")
        #expect(value("environment")?.contains("Graphics backend: d3dmetal") == true)
        #expect(value("environment")?.contains("Chip: Apple M3 Pro") == true)
    }

    @Test("Every field the link fills exists in the issue form")
    func formHasTheFields() throws {
        let form = try String(contentsOf: Repo.root.appendingPathComponent(".github/ISSUE_TEMPLATE/compatibility-report.yml"),
                              encoding: .utf8)
        for id in ["game", "outcome", "environment", "details"] {
            #expect(form.contains("id: \(id)"), "issue form has no field '\(id)'")
        }
        #expect(form.contains(CompatibilityReport.label))
    }

    @Test("The prompt is asked once per game and setup")
    func askedOnce() {
        TestHome.ensure()
        let slug = "asked-\(UUID().uuidString.prefix(8))"
        let setup = CompatibilityReport.setupKey(cellarVersion: "0.2.0", runner: "wineforge", backend: "d3dmetal")
        #expect(CompatibilityReport.shouldAsk(slug: slug, setup: setup))
        CompatibilityReport.markAsked(slug: slug, setup: setup)
        #expect(!CompatibilityReport.shouldAsk(slug: slug, setup: setup))
        let switched = CompatibilityReport.setupKey(cellarVersion: "0.2.0", runner: "wineforge", backend: "dxvk")
        #expect(CompatibilityReport.shouldAsk(slug: slug, setup: switched), "a new backend is a new setup")
    }
}
