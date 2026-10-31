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

/// The game's log, live: what Cellar did for it and the tail of Wine's output, re-read every two
/// seconds while it is open. Copy for a forum post, or the full diagnostics report for an issue.
struct GameLogSection: View {
    let game: GameSummary
    @State private var expanded = false
    @State private var text = ""
    @State private var saved: URL?
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    Text(text.isEmpty ? String(localized: "Nothing logged for \(game.name) yet.") : text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                .frame(height: 220)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 10) {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    .disabled(text.isEmpty)
                    Button("Save Diagnostics Report") { saveReport() }
                    if let saved {
                        Button("Show \(saved.lastPathComponent)") { NSWorkspace.shared.activateFileViewerSelecting([saved]) }
                            .buttonStyle(.link)
                    }
                    Spacer()
                }
                Text("Account names, your home folder and anything token-shaped are left out of both.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } label: {
            Label("Game log", systemImage: "doc.text.magnifyingglass").font(.callout)
        }
        .onChange(of: expanded) { open in if open { refresh() } }
        .onReceive(tick) { _ in if expanded { refresh() } }
    }

    private func refresh() {
        let slug = game.slug
        Task.detached(priority: .utility) {
            let log = Diagnostics.sessionLog(slug: slug)
            await MainActor.run { text = log }
        }
    }

    private func saveReport() {
        Task.detached(priority: .userInitiated) {
            let url = try? Diagnostics.exportReport(cellarVersion: CellarVersion.current)
            await MainActor.run { saved = url }
        }
    }
}
