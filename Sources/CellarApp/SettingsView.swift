import SwiftUI
import AppKit
import CellarKit
import CellarUI

struct SettingsView: View {
    @AppStorage("showHUD") private var showHUD = false
    /// Settings is shown in a standalone NSWindow (not a SwiftUI sheet — that crashes under
    /// NSHostingView), so Done closes the window through this callback rather than `dismiss`.
    var onClose: () -> Void = {}

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
                    Button("Open logs") {
                        NSWorkspace.shared.open(Paths.logs)
                    }
                }
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
        .frame(width: 460, height: 500)
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }
}
