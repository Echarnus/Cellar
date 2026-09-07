import SwiftUI
import CellarKit

struct GameDetailView: View {
    let game: GameSummary
    @ObservedObject var runner: CellarRunner
    let onChange: () -> Void
    @AppStorage("showHUD") private var showHUD = false
    @State private var showDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 18) {
                    actions
                    Text(hint).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    chips
                    DisclosureGroup(isExpanded: $showDetails) {
                        ScrollView {
                            Text(runner.log.isEmpty ? "Ready." : runner.log)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        }.frame(height: 200)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    } label: { Label("Activity log", systemImage: "terminal").font(.callout) }
                }.padding(24)
            }
        }
        .background(.background)
    }

    // Hero banner with the game's Steam hero art, a gradient scrim, cover + title overlaid.
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteArt(Artwork.hero(game.appID)) {
                LinearGradient(colors: [.pink.opacity(0.35), .purple.opacity(0.25)], startPoint: .top, endPoint: .bottom)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 16) {
                RemoteArt(Artwork.portrait(game.appID)) { GameIcon(path: game.iconPath, size: 92) }
                    .frame(width: 92, height: 138)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text(game.name).font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(.white).shadow(radius: 4).lineLimit(2)
                    if let acc = game.account {
                        Text("Signed in as \(acc)").font(.caption).foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
            }.padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipped()
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button { primary() } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon).font(.title3)
                    Text(game.nextStep.rawValue).fontWeight(.semibold)
                }.frame(minWidth: 150).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .tint(game.nextStep == .play ? .green : .accentColor)
            .disabled(runner.busy)
            .keyboardShortcut(.defaultAction)

            if runner.busy {
                ProgressView().controlSize(.small)
                Text(runner.busyTitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Set up bottle") { act(["setup", "--profile", game.slug], "Setting up") }
                Button("Open Steam") { act(["steam", "open", game.slug], "Opening Steam") }
                Button("Install game") { act(["steam", "install", game.slug], "Installing") }
                if game.appID != nil { Button("Download (no Steam)…") { act(["steam", "install", game.slug], "Installing") } }
                Button("Add to Steam library") { act(["steam", "add", game.slug], "Adding") }
            } label: { Image(systemName: "ellipsis.circle").font(.title3) }
            .menuStyle(.borderlessButton).fixedSize()
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            Chip(game.nextStep == .play ? "Ready to play" : "Setup required",
                 system: game.nextStep == .play ? "checkmark.circle.fill" : "wrench.and.screwdriver",
                 tint: game.nextStep == .play ? .green : .orange)
            Chip(game.appID.map { "AppID \($0)" } ?? "No AppID", system: "number")
        }
    }

    private var icon: String { game.nextStep == .play ? "play.fill" : "arrow.down.circle.fill" }
    private var hint: String {
        switch game.nextStep {
        case .setup:   return "First, Cellar installs the runtime and Steam for this game — one click, a few minutes."
        case .login:   return "Sign in to Steam (a window opens; the QR code with the Steam mobile app is quickest)."
        case .install: return "Install the game — Cellar downloads it. You already own it on Steam."
        case .play:    return "Ready. Play launches the game and closes everything when you quit."
        }
    }

    private func primary() {
        switch game.nextStep {
        case .play:    act(["launch", game.slug] + (showHUD ? ["--hud"] : []), "Launching")
        case .install: act(["steam", "install", game.slug], "Installing")
        case .login:   act(["steam", "open", game.slug], "Opening Steam")
        case .setup:   act(["setup", "--profile", game.slug], "Setting up")
        }
    }
    private func act(_ args: [String], _ title: String) { runner.run(args, title: title) { onChange() } }
}

struct Chip: View {
    let text: String; let system: String; var tint: Color = .secondary
    init(_ text: String, system: String, tint: Color = .secondary) { self.text = text; self.system = system; self.tint = tint }
    var body: some View {
        Label(text, systemImage: system).font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(tint.opacity(0.15), in: Capsule()).foregroundStyle(tint == .secondary ? .secondary : tint)
    }
}
