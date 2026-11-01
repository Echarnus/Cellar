import CellarDomain
import AppKit
import SwiftUI
import CellarData

/// The game's log, live: what Cellar did for it and the tail of Wine's output, re-read every two
/// seconds while it is open. Copy for a forum post, or the full diagnostics report for an issue.
struct GameLogSection: View {
    let game: GameSummary
    @State private var expanded: Bool

    init(game: GameSummary, expanded: Bool = false) {
        self.game = game
        _expanded = State(initialValue: expanded)
    }
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
        .task { if expanded { refresh() } }
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
