import SwiftUI
import AppKit
import CellarKit

/// Settings — and, first of all, **the** sign-in.
///
/// Accounts used to be a window of their own, reached from a menu item most people never opened,
/// while the library asked for a sign-in per game. Signing in is the first thing Cellar needs and
/// the thing a player goes looking for later, so it is the first section of the one window called
/// Settings. There is no second place to sign in.
struct SettingsView: View {
    @AppStorage("showHUD") private var showHUD = false
    /// Settings is shown in a standalone NSWindow (not a SwiftUI sheet — that crashes under
    /// NSHostingView), so Done closes the window through this callback rather than `dismiss`.
    var onClose: () -> Void = {}

    @StateObject private var runner = CellarRunner()
    /// Read once per refresh, never from a view body — see `StoreAccountState`.
    @State private var accounts = StoreAccountState.unknown

    private var runnerName: String { RunnerManager.installed().first?.spec.displayName ?? "not installed" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.title2.weight(.bold))
                Spacer()
                Button("Done") { onClose() }.keyboardShortcut(.defaultAction)
            }.padding(20)
            Divider()
            Form {
                Section("Account") {
                    AccountsSection(runner: runner, state: accounts, refresh: refresh)
                        .padding(.vertical, 4)
                }
                Section("Gameplay") {
                    Toggle("Show Metal performance overlay (FPS)", isOn: $showHUD)
                    Text("Adds an on-screen FPS/frametime HUD when launching a game.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Runtime") {
                    LabeledContent("Wine runner", value: runnerName)
                    Button("Open Cellar folder") { NSWorkspace.shared.open(Paths.appSupport) }
                    Button("Open logs") { NSWorkspace.shared.open(Paths.logs) }
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
            Divider()
            activity
        }
        // A *fixed* size, and the window is not resizable. A flexible root frame inside
        // NSHostingView lets layout feed back into the view graph, and this app aborts in
        // AttributeGraph when that happens (skills/swift.md). Not worth being clever about.
        .frame(width: 560, height: 680)
        .onAppear(perform: refresh)
    }

    /// Always present, at a fixed height, rather than appearing when something happens: a pane that
    /// materialises mid-run changes the view tree's shape during layout, which is what this app
    /// crashes on. Empty, it explains itself.
    private var activity: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if runner.busy {
                    ProgressView().controlSize(.small)
                    Text(runner.busyTitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.top, 8)
            ScrollView {
                Text(runner.log.isEmpty ? "Anything Cellar runs shows up here." : runner.log)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(runner.log.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 92)
        }
        .background(Color.primary.opacity(0.04))
    }

    /// Re-read every store's state, **off the main thread and after layout has finished**.
    ///
    /// This work is not cheap — it stats bottles, reads the keychain, and asks GOG for a username
    /// over the network. Doing it inline in `onAppear` meant blocking the main thread and then
    /// mutating `@State` in the middle of `NSHostingView`'s first layout pass, which re-enters the
    /// view graph and aborts in AttributeGraph.
    private func refresh() {
        Task.detached {
            if GOGAuth.isSignedIn, GOGAuth.cachedUsername == nil {
                GOGAuth.cacheUsername(try? GOGAuth.username())
            }
            let snapshot = StoreAccountState.current()
            await MainActor.run { accounts = snapshot }
        }
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }
}
