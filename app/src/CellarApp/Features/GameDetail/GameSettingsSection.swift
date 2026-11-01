import CellarDomain
import AppKit
import SwiftUI
import CellarData

/// The game page's display and performance switches. Each is one `PerformanceSetting`, written into
/// the bottle (`bottle.toml`) exactly as `cellar perf set` writes it, so the app and the CLI can
/// never disagree about what a game will get. Applies from the next launch.
///
/// Writes through CellarData directly, like the language picker: one line in a settings file, and
/// the runner refuses work while a game is playing.
///
/// The page shows the switches a player picks for taste; `advanced` is the copy in Technical Details,
/// which holds the one that only exists to work around a crash.
struct GameSettingsSection: View {
    let game: GameSummary
    var advanced = false

    /// Loaded after the first layout, never from the body (skills/swift.md).
    @State private var values: [PerformanceSetting: String] = [:]
    @State private var failure: String?
    /// The switches this game's profile turns on to stop a crash — said beside the switch, so
    /// turning one off is never a surprise.
    @State private var crashWorkarounds: Set<PerformanceSetting> = []

    private struct Row {
        let setting: PerformanceSetting
        let title: String
        let tradeOff: String
    }

    private var rows: [Row] {
        let all = allRows
        return advanced ? all.filter { $0.setting == .metalValidation } : all.filter { $0.setting != .metalValidation }
    }

    private var allRows: [Row] {
        var rows = [
            Row(setting: .retina, title: String(localized: "Retina resolution"),
                tradeOff: String(localized: "Renders at your display's full pixel density. Sharper, and up to four times the work for the GPU.")),
            Row(setting: .metalHUD, title: String(localized: "Show frame rate"),
                tradeOff: String(localized: "Metal's overlay with frames per second and frame time. Costs next to nothing.")),
            Row(setting: .metalValidation, title: String(localized: "Metal validation"),
                tradeOff: String(localized: "Checks every graphics call. Slower, but it stops some games crashing on D3DMetal.")),
        ]
        if game.backend == GraphicsBackend.d3dmetal.rawValue {
            rows.insert(Row(setting: .metalFXUpscaling, title: String(localized: "MetalFX upscaling"),
                            tradeOff: String(localized: "Appears as DLSS in the game's own settings: renders smaller and upscales. Faster, slightly softer.")),
                        at: 1)
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(advanced ? String(localized: "Graphics fixes") : String(localized: "Display and performance")).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                .kerning(0.5).textCase(.uppercase)
            ForEach(rows, id: \.setting) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(row.title, isOn: binding(row.setting))
                    Text(row.tradeOff).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if crashWorkarounds.contains(row.setting) {
                        Text("\(game.name) needs this on: without it, it crashes as it starts. If you switch it off and that happens, Cellar switches it back on.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("Changes apply the next time \(game.name) starts.")
                .font(.caption).foregroundStyle(.secondary)
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .task(id: game.slug) { load() }
    }

    private func binding(_ setting: PerformanceSetting) -> Binding<Bool> {
        Binding(get: { values[setting] == "true" }, set: { save(setting, $0) })
    }

    private func load() {
        guard let plan = try? Game.plan(slug: game.slug) else { return }
        values = Dictionary(uniqueKeysWithValues: plan.performance.entries.map { ($0.setting, $0.value) })
        crashWorkarounds = Set(plan.performance.crashWorkaroundsInProfile)
    }

    private func save(_ setting: PerformanceSetting, _ on: Bool) {
        do {
            try BottleConfig.set(setting, to: on ? "true" : "false", in: BottleConfig.url(forBottle: game.bottleName))
            values[setting] = on ? "true" : "false"
            failure = nil
            // The CLI logs every `cellar perf set`; a switch flipped here has to leave the same trace,
            // or a game that stops starting has no record of why.
            CellarLog.info(.app, "\(setting.key) set to \(on) for \(game.name) in the app.", subject: game.slug)
        } catch {
            failure = "Couldn't save that: \(CellarLog.describe(error))"
        }
    }
}
