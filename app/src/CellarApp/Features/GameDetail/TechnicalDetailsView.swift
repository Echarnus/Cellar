import CellarDomain
import AppKit
import SwiftUI
import CellarData

/// Everything about a game that is there for fixing it rather than playing it: the runner, the
/// graphics layer and the Windows set-up Cellar made for it, the store's own id for it, what the
/// profile's author wrote down, the one switch that only exists to work around a crash, and the
/// logs with the report to attach to an issue.
struct TechnicalDetailsView: View {
    static let width: CGFloat = 640
    static let height: CGFloat = 700

    let game: GameSummary
    let runner: ActivityStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("How Cellar runs \(game.name). You don't need any of this to play — it's here for fixing a game that won't start, and for reporting a problem.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 32) {
                    FactList(title: String(localized: "Runtime"), rows: runtime)
                    if !game.facts.technical.isEmpty {
                        FactList(title: String(localized: "The game"), rows: game.facts.technical)
                    }
                    Spacer(minLength: 0)
                }

                if let notes = game.facts.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text("Profile notes").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                .kerning(0.5).textCase(.uppercase)
                            if let status = game.facts.status { StatusBadge(status: status) }
                        }
                        Text(notes).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }

                if game.bottleExists { GameSettingsSection(game: game, advanced: true) }

                GameLogSection(game: game, expanded: true)

                VStack(alignment: .leading, spacing: 6) {
                    Label("Activity log", systemImage: "terminal").font(.callout)
                    ScrollView {
                        Text(runner.log.isEmpty ? String(localized: "Nothing has run yet.") : runner.log)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                    .frame(height: 200)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
        }
        .frame(width: Self.width, height: Self.height)
        .background(.background)
    }

    /// The pieces Cellar assembled for this game, in the words a bug report uses.
    private var runtime: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [
            ("Runner", game.runnerID),
            ("Graphics", graphicsValue),
            ("Store", game.store.displayName),
        ]
        switch game.store {
        case .steam:
            if let appID = game.appID { rows.append(("AppID", String(appID))) }
        case .battlenet:
            if let code = game.productCode { rows.append(("Product code", code)) }
        case .gog:
            break
        }
        rows.append(("Bottle", game.bottleName))
        return rows
    }

    /// The backend, and whose choice it is — a switch the player made is never shown as the profile's.
    private var graphicsValue: String {
        let name = GraphicsBackend(rawValue: game.backend)?.displayName ?? game.backend
        return game.backendIsPlayerChoice ? String(localized: "\(name) — your choice") : name
    }
}
