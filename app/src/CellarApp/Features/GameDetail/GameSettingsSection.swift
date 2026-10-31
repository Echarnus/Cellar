import CellarDomain
import AppKit
import SwiftUI
import CellarKit

/// The game page's display and performance switches. Each is one `PerformanceSetting`, written into
/// the bottle (`bottle.toml`) exactly as `cellar perf set` writes it, so the app and the CLI can
/// never disagree about what a game will get. Applies from the next launch.
///
/// Writes through CellarKit directly, like the language picker: one line in a settings file, and
/// the runner refuses work while a game is playing.
struct GameSettingsSection: View {
    let game: GameSummary

    /// Loaded after the first layout, never from the body (skills/swift.md).
    @State private var values: [PerformanceSetting: String] = [:]
    @State private var failure: String?

    private struct Row {
        let setting: PerformanceSetting
        let title: String
        let tradeOff: String
    }

    private var rows: [Row] {
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
            Text("Display and performance").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                .kerning(0.5).textCase(.uppercase)
            ForEach(rows, id: \.setting) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(row.title, isOn: binding(row.setting))
                    Text(row.tradeOff).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Changes apply the next time \(game.name) starts. Fast sync is always on when the runner has one.")
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
    }

    private func save(_ setting: PerformanceSetting, _ on: Bool) {
        do {
            try BottleConfig.set(setting, to: on ? "true" : "false", in: BottleConfig.url(forBottle: game.bottleName))
            values[setting] = on ? "true" : "false"
            failure = nil
        } catch {
            failure = "Couldn't save that: \(CellarLog.describe(error))"
        }
    }
}
