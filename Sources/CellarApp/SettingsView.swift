import SwiftUI
import AppKit
import CellarKit

struct SettingsView: View {
    @AppStorage("showHUD") private var showHUD = false
    /// Settings is shown in a standalone NSWindow (not a SwiftUI sheet — that crashes under
    /// NSHostingView), so Done closes the window through this callback rather than `dismiss`.
    var onClose: () -> Void = {}

    /// Where the diagnostics export has got to. Every one of these states is drawn: a button that
    /// silently writes a file somewhere is a button the player can't trust.
    private enum Export: Equatable {
        case idle, working
        case written(URL)
        case failed(String)
    }
    @State private var export: Export = .idle

    private var runnerName: String { RunnerManager.installed().first?.spec.displayName ?? "not installed" }
    private var depot: String { DepotTool.isInstalled ? "installed" : "installs on first download" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.title2.weight(.bold))
                Spacer()
                Button("Done") { onClose() }.keyboardShortcut(.defaultAction)
            }.padding(20)
            Divider()
            Form {
                Section("Gameplay") {
                    Toggle("Show Metal performance overlay (FPS)", isOn: $showHUD)
                    Text("Adds an on-screen FPS/frametime HUD when launching a game.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Runtime") {
                    LabeledContent("Wine runner", value: runnerName)
                    LabeledContent("DepotDownloader", value: depot)
                    Button("Open Cellar folder") {
                        NSWorkspace.shared.open(Paths.appSupport)
                    }
                }
                diagnostics
                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    Link("Cellar on GitHub", destination: URL(string: "https://github.com/Echarnus/Cellar")!)
                    Link("Supported games", destination: URL(string: "https://echarnus.github.io/Cellar/")!)
                    Text("Windows games on Apple Silicon via Wine + Apple D3DMetal. GPL-3.0. Not affiliated with Valve or Apple.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 460, height: 660)
    }

    // MARK: - Diagnostics

    /// Cellar keeps a rolling record of set-ups, launches and failures. This is where a player
    /// turns that into one file they can attach to a bug report — the whole reason it is kept.
    @ViewBuilder private var diagnostics: some View {
        Section("Diagnostics") {
            LabeledContent("Kept log", value: logSize)
            HStack {
                Button("Export diagnostics…") { exportReport() }
                    .disabled(export == .working)
                Button("Open logs folder") { NSWorkspace.shared.open(Paths.logs) }
            }
            Text("Writes one text file — your Mac's details, Cellar's log of what it did, and the "
                + "tail of each Wine log — to your Desktop. Account names, your home folder path "
                + "and anything token-shaped are left out.")
                .font(.caption).foregroundStyle(.secondary)

            switch export {
            case .idle:
                EmptyView()
            case .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Collecting…").font(.caption).foregroundStyle(.secondary)
                }
            case .written(let url):
                HStack(spacing: 8) {
                    Text("✓").foregroundStyle(.green)
                    Text("Saved \(url.lastPathComponent) to your Desktop.").font(.caption)
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }.controlSize(.small)
                }
            case .failed(let reason):
                HStack(spacing: 8) {
                    Text("✗").foregroundStyle(.red)
                    Text(reason).font(.caption).textSelection(.enabled)
                }
            }
        }
    }

    private var logSize: String {
        let bytes = CellarLog.historySize
        if bytes == 0 { return "nothing logged yet" }
        return bytes < 1024 ? "\(bytes) bytes" : "\(bytes / 1024) KB"
    }

    /// Off the main thread: the report shells out to `sysctl`, `arch` and `gh`, and a Settings
    /// window that beachballs while doing it would be its own bug.
    private func exportReport() {
        export = .working
        let version = appVersion
        Task.detached {
            do {
                let url = try Diagnostics.exportReport(cellarVersion: version)
                await MainActor.run { export = .written(url) }
            } catch {
                await MainActor.run { export = .failed(CellarLog.describe(error)) }
            }
        }
    }

    private var appVersion: String { Bundle.main.shortVersion }
}
