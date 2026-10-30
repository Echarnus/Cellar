import Foundation

/// A player's word on how a game ran, turned into a GitHub issue they file themselves.
///
/// The profile database is only as good as its verified facts, and a profile marked "untested"
/// stays that way until somebody tells us otherwise. Players are the best source — but nothing here
/// sends anything. Cellar builds the text, the player reads every line of it, and their browser
/// opens GitHub's new-issue form with it filled in. They press Submit, or they don't.
///
/// What goes in: the game, its store, the runner and graphics backend Cellar used, macOS, the chip
/// and Cellar's version. What never does: account names, paths under the home folder, tokens —
/// everything, the player's own notes included, goes through `Diagnostics.redact` and the known
/// account names are taken out by name.
public enum CompatibilityReport {

    public enum Outcome: String, CaseIterable, Sendable {
        case works
        case issues
        case didNotStart = "didnt-start"

        /// The phrase in the issue's title and its outcome field.
        public var title: String {
            switch self {
            case .works:       return "Works"
            case .issues:      return "Runs with issues"
            case .didNotStart: return "Didn't start"
            }
        }
    }

    /// Everything a report says, before it is rendered.
    public struct Facts: Sendable, Equatable {
        public var game: String
        public var slug: String
        public var store: String
        public var runner: String
        public var backend: String
        public var profileStatus: String?
        public var macOS: String
        public var chip: String
        public var cellarVersion: String
        public var outcome: Outcome
        public var notes: String?

        public init(game: String, slug: String, store: String, runner: String, backend: String,
                    profileStatus: String?, macOS: String = SystemEnvironment.macOSVersionString,
                    chip: String = SystemEnvironment.chipBrand, cellarVersion: String = CellarVersion.current,
                    outcome: Outcome, notes: String? = nil) {
            self.game = game; self.slug = slug; self.store = store; self.runner = runner
            self.backend = backend; self.profileStatus = profileStatus; self.macOS = macOS
            self.chip = chip; self.cellarVersion = cellarVersion; self.outcome = outcome; self.notes = notes
        }

        public init(_ game: GameSummary, outcome: Outcome, notes: String? = nil) {
            self.init(game: game.name, slug: game.slug, store: game.store.displayName, runner: game.runnerID,
                      backend: game.backend, profileStatus: game.facts.status, outcome: outcome, notes: notes)
        }

        public init(_ plan: GamePlan, outcome: Outcome, notes: String? = nil) {
            self.init(game: plan.name, slug: plan.slug, store: plan.store.displayName, runner: plan.runnerID,
                      backend: plan.backend, profileStatus: plan.facts.status, outcome: outcome, notes: notes)
        }
    }

    /// The repository reports are filed against, and the issue form that receives them.
    static let newIssue = "https://github.com/Echarnus/Cellar/issues/new"
    static let template = "compatibility-report.yml"
    public static let label = "compatibility-report"

    public static func title(_ facts: Facts) -> String {
        clean("\(facts.game): \(facts.outcome.title.lowercased()) on macOS \(facts.macOS)")
    }

    /// The environment block — what the player sees in the preview and what fills the form's
    /// `environment` field. Plain lines, so it reads the same in a dialog and on GitHub.
    public static func environment(_ facts: Facts) -> String {
        var lines = [
            "Game: \(facts.game) (profile \(facts.slug), \(facts.store))",
            "Outcome: \(facts.outcome.title)",
            "Runner: \(facts.runner)",
            "Graphics backend: \(facts.backend)",
            "macOS: \(facts.macOS)",
            "Chip: \(facts.chip.isEmpty ? "unknown" : facts.chip)",
            "Cellar: \(facts.cellarVersion)",
        ]
        if let status = facts.profileStatus, !status.isEmpty { lines.append("Profile status: \(status)") }
        return clean(lines.joined(separator: "\n"))
    }

    /// The player's own words, cleaned the same way.
    public static func details(_ facts: Facts) -> String {
        clean(facts.notes ?? "")
    }

    /// GitHub's new-issue form for a compatibility report, filled in. Opening it sends nothing;
    /// the player submits it on GitHub, or closes the tab.
    public static func issueURL(_ facts: Facts) -> URL {
        var components = URLComponents(string: newIssue)!
        components.queryItems = [
            URLQueryItem(name: "template", value: template),
            URLQueryItem(name: "labels", value: label),
            URLQueryItem(name: "title", value: title(facts)),
            URLQueryItem(name: "game", value: clean("\(facts.game) (\(facts.slug))")),
            URLQueryItem(name: "outcome", value: facts.outcome.title),
            URLQueryItem(name: "environment", value: environment(facts)),
            URLQueryItem(name: "details", value: details(facts)),
        ]
        return components.url!
    }

    /// Redaction for anything that leaves the Mac: `Diagnostics.redact`, then every account name
    /// Cellar knows of, by name — a Steam login is not a credential-shaped `key=value`, so the
    /// general pass would let it through.
    static func clean(_ text: String) -> String {
        var out = Diagnostics.redact(text)
        for name in knownAccountNames where name.count >= 3 {
            out = out.replacingOccurrences(of: name, with: "<account>", options: .caseInsensitive)
        }
        return out
    }

    /// Overridable so a test can prove an account name is removed without signing in.
    nonisolated(unsafe) static var knownAccountNames: [String] = {
        [SteamAccount.record?.accountName].compactMap { $0 }
    }()

    // MARK: - Asking once

    /// What "this version of the game" means for the prompt: the Cellar, runner and backend it ran
    /// on. A player asked about a setup is not asked again until one of those changes.
    public static func setupKey(cellarVersion: String = CellarVersion.current, runner: String, backend: String) -> String {
        "\(cellarVersion)/\(runner)/\(backend)"
    }

    static var askedFile: URL { Paths.appSupport.appendingPathComponent("compatibility-asked.json") }

    /// Whether the after-session prompt is due for this game on this setup.
    public static func shouldAsk(slug: String, setup: String) -> Bool {
        asked()[slug] != setup
    }

    /// Record that the player was asked, whatever they answered — "Not now" included.
    public static func markAsked(slug: String, setup: String) {
        var all = asked()
        all[slug] = setup
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
        try? data.write(to: askedFile, options: .atomic)
    }

    static func asked() -> [String: String] {
        guard let data = try? Data(contentsOf: askedFile),
              let all = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return all
    }
}
