import SwiftUI
import AppKit
import CellarKit

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
                // Signing in is account-level, so it belongs here as well as behind ⌘⇧A — the
                // welcome tour promises "you can do this later in Settings", and this is that.
                Section("Accounts") {
                    Button("Manage accounts…") {
                        NotificationCenter.default.post(name: .cellarOpenAccounts, object: nil)
                    }
                    Text("Sign in to Steam, GOG or Battle.net — once per store, for your whole library. Also at ⌘⇧A.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                Section("Help") {
                    Button("Show the welcome tour again") {
                        NotificationCenter.default.post(name: .cellarOpenWelcomeTour, object: nil)
                    }
                    Link("Questions & answers", destination: URL(string: "https://echarnus.github.io/Cellar/faq.html")!)
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
        .frame(width: 460, height: 700)
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }
}
