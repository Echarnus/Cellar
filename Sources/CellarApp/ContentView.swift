import SwiftUI
import AppKit
import CellarKit

struct ContentView: View {
    @StateObject private var runner = CellarRunner()
    @State private var games: [GameSummary] = []
    @State private var selectedSlug: String?

    private var current: GameSummary? { games.first { $0.slug == selectedSlug } }

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 220, maxWidth: 300)
            detail.frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 480)
        .onAppear { refresh(); if selectedSlug == nil { selectedSlug = games.first?.slug } }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cellar").font(.headline)
                Spacer()
                Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }.padding(10)
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(games) { game in
                        Button { selectedSlug = game.slug } label: {
                            HStack(spacing: 10) {
                                GameIcon(path: game.iconPath, size: 32)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(game.name).lineLimit(1)
                                    Text(statusLine(game)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(6)
                            .background(selectedSlug == game.slug ? Color.accentColor.opacity(0.15) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }.padding(8)
            }
            if !runner.binaryExists {
                Divider()
                Text("`cellar` CLI not found. Build with `swift build -c release`.")
                    .font(.caption).foregroundStyle(.red).padding(8)
            }
        }
    }

    private var detail: some View {
        Group {
            if let game = current {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        GameIcon(path: game.iconPath, size: 88)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.name).font(.title.bold())
                            Text(statusLine(game)).foregroundStyle(.secondary)
                            if let acc = game.account {
                                Text("Signed in as \(acc)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        primaryButton(game)
                        Menu("More") {
                            Button("Set up bottle") { runner.run(["setup", "--profile", game.slug], title: "Setting up") { refresh() } }
                            Button("Open Steam")    { runner.run(["steam", "open", game.slug], title: "Opening Steam") }
                            Button("Install game")  { runner.run(["steam", "install", game.slug], title: "Installing") }
                            Button("Add to Steam")  { runner.run(["steam", "add", game.slug], title: "Adding to Steam") { refresh() } }
                            Button("Status")        { runner.run(["steam", "status", game.slug], title: "Status") }
                        }.frame(width: 90)
                        if runner.busy {
                            ProgressView().controlSize(.small)
                            Text(runner.busyTitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    GroupBox("Output") {
                        ScrollView {
                            Text(runner.log.isEmpty ? "Ready." : runner.log)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(4)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "gamecontroller").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("Choose a game").font(.title2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func primaryButton(_ game: GameSummary) -> some View {
        let step = game.nextStep
        return Button {
            switch step {
            case .play:    runner.run(["launch", game.slug], title: "Launching")
            case .install: runner.run(["steam", "install", game.slug], title: "Installing")
            case .login:   runner.run(["steam", "open", game.slug], title: "Opening Steam to log in")
            case .setup:   runner.run(["setup", "--profile", game.slug], title: "Setting up") { refresh() }
            }
        } label: {
            Label(step.rawValue, systemImage: step == .play ? "play.fill" : "arrow.down.circle")
                .frame(minWidth: 110)
        }
        .buttonStyle(.borderedProminent)
        .tint(step == .play ? .green : .accentColor)
        .disabled(runner.busy)
    }

    private func statusLine(_ g: GameSummary) -> String {
        if !g.runnerInstalled { return "Runner not installed" }
        if !g.steamInstalled { return "Bottle not set up" }
        if g.account == nil { return "Not signed in" }
        if !g.gameInstalled { return "Not installed" }
        return "Ready to play"
    }

    private func refresh() { games = Game.summaries() }
}

/// A game's icon from its extracted `.icns`, with a placeholder fallback.
struct GameIcon: View {
    let path: String?
    let size: CGFloat
    var body: some View {
        ZStack {
            if let path, let img = NSImage(contentsOfFile: path) {
                Image(nsImage: img).resizable()
            } else {
                RoundedRectangle(cornerRadius: size * 0.22).fill(.quaternary)
                Image(systemName: "gamecontroller.fill").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }
}
