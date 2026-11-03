import CellarDomain
import AppKit
import SwiftUI
import CellarData
import CellarUI

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
    /// Whether Cellar can start this game full screen or in a window (`GamePlan.canChooseDisplayMode`).
    /// When it can't, the page says only how to switch while playing — never a picker that does nothing.
    @State private var canChooseDisplay = false

    /// The switches this page shows, in order. MetalFX only where the game runs on D3DMetal, the one
    /// backend that offers it.
    private var settings: [PerformanceSetting] {
        if advanced { return [.metalValidation] }
        return game.backend == GraphicsBackend.d3dmetal.rawValue
            ? [.retina, .metalFXUpscaling, .metalHUD] : [.retina, .metalHUD]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(advanced ? String(localized: "Graphics fixes") : String(localized: "Display and performance")).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                .kerning(0.5).textCase(.uppercase)
            if !advanced { displayModeRow }
            ForEach(settings, id: \.self) { setting in
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(setting.displayTitle, isOn: binding(setting))
                    Text(setting.tradeOff).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if crashWorkarounds.contains(setting) {
                        Text("\(game.name) needs this on: without it, it crashes as it starts. If you switch it off and that happens, Cellar switches it back on.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text(advanced ? String(localized: "Changes apply the next time \(game.name) starts.")
                          : String(localized: "Changes apply the next time \(game.name) starts. Settings holds the same switches for every game."))
                .font(.caption).foregroundStyle(.secondary)
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .task(id: game.slug) { load() }
    }

    /// Full screen or a window: chosen here for the next start, switched with ⌘Return while playing.
    @ViewBuilder private var displayModeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if canChooseDisplay {
                HStack(spacing: 10) {
                    Text(PerformanceSetting.displayMode.displayTitle)
                    EqualSegmentedPicker(DisplayMode.allCases.map(\.displayTitle), selection: displayModeIndex,
                                         accessibilityLabel: String(localized: "Start \(game.name) in"))
                        .frame(maxWidth: 320)
                }
                Text(PerformanceSetting.displayMode.tradeOff).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(DisplayMode.whilePlayingHint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayModeIndex: Binding<Int> {
        Binding(get: {
            DisplayMode.allCases.firstIndex { $0.rawValue == values[.displayMode] } ?? 0
        }, set: { index in
            guard DisplayMode.allCases.indices.contains(index) else { return }
            save(.displayMode, DisplayMode.allCases[index].rawValue)
        })
    }

    private func binding(_ setting: PerformanceSetting) -> Binding<Bool> {
        Binding(get: { values[setting] == "true" }, set: { save(setting, $0) })
    }

    private func load() {
        guard let plan = try? Game.plan(slug: game.slug) else { return }
        values = Dictionary(uniqueKeysWithValues: plan.performance.entries.map { ($0.setting, $0.value) })
        crashWorkarounds = Set(plan.performance.crashWorkaroundsInProfile)
        canChooseDisplay = plan.canChooseDisplayMode
    }

    private func save(_ setting: PerformanceSetting, _ on: Bool) {
        save(setting, on ? "true" : "false")
    }

    private func save(_ setting: PerformanceSetting, _ value: String) {
        do {
            try BottleConfig.set(setting, to: value, in: BottleConfig.url(forBottle: game.bottleName))
            values[setting] = value
            failure = nil
            // The CLI logs every `cellar perf set`; a switch flipped here has to leave the same trace,
            // or a game that stops starting has no record of why.
            CellarLog.info(.app, "\(setting.key) set to \(value) for \(game.name) in the app.", subject: game.slug)
        } catch {
            failure = "Couldn't save that: \(CellarLog.describe(error))"
        }
    }
}
