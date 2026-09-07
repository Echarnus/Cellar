import SwiftUI
import AppKit
import CellarKit

@MainActor
final class Library: ObservableObject {
    @Published var games: [GameSummary] = []
    @Published var query = ""
    @Published var filter: Filter = .all
    @Published var selected: String?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", ready = "Ready", installed = "Installed", notInstalled = "Not installed"
        var id: String { rawValue }
    }

    func refresh() {
        games = Game.summaries()
        if selected == nil || !games.contains(where: { $0.slug == selected }) {
            selected = filtered.first?.slug ?? games.first?.slug
        }
    }

    var filtered: [GameSummary] {
        games.filter { g in
            (query.isEmpty || g.name.localizedCaseInsensitiveContains(query)) && {
                switch filter {
                case .all: return true
                case .ready: return g.nextStep == .play
                case .installed: return g.gameInstalled
                case .notInstalled: return !g.gameInstalled
                }
            }()
        }
    }
    var current: GameSummary? { games.first { $0.slug == selected } }
}

struct ContentView: View {
    @StateObject private var lib = Library()
    @StateObject private var runner = CellarRunner()
    @State private var showSettings = false

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 260, maxWidth: 320)
            Group {
                if let game = lib.current {
                    GameDetailView(game: game, runner: runner) { lib.refresh() }.id(game.slug)
                } else { EmptyState() }
            }.frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear { lib.refresh() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "wineglass.fill").foregroundStyle(.pink)
                Text("Cellar").font(.system(.title3, design: .rounded).weight(.bold))
                Spacer()
                Button { lib.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Refresh")
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).help("Settings")
            }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Search games", text: $lib.query).textFieldStyle(.plain)
            }
            .padding(7).background(.quaternary, in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 12)

            Picker("", selection: $lib.filter) {
                ForEach(Library.Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 12).padding(.vertical, 8)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(lib.filtered) { game in
                        SidebarRow(game: game, selected: lib.selected == game.slug)
                            .contentShape(Rectangle())
                            .onTapGesture { lib.selected = game.slug }
                    }
                    if lib.filtered.isEmpty {
                        Text("No games match.").font(.caption).foregroundStyle(.secondary).padding(.top, 20)
                    }
                }.padding(8)
            }
            Divider()
            HStack {
                Text("\(lib.games.count) games").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !runner.binaryExists {
                    Label("CLI missing", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }.padding(.horizontal, 14).padding(.vertical, 8)
        }
        .background(.background)
    }
}

struct SidebarRow: View {
    let game: GameSummary
    let selected: Bool
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 10) {
            RemoteArt(Artwork.portrait(game.appID)) { GameIcon(path: game.iconPath, size: 34) }
                .frame(width: 34, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name).lineLimit(1).font(.callout.weight(.medium))
                StatusPill(game: game, compact: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(selected ? Color.accentColor.opacity(0.20)
                             : (hovering ? Color.primary.opacity(0.06) : Color.clear),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }
}

struct StatusPill: View {
    let game: GameSummary
    var compact = false
    var body: some View {
        let (text, color) = state
        if compact {
            Text(text).font(.caption2).foregroundStyle(color)
        } else {
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(color, in: Capsule())
        }
    }
    private var state: (String, Color) {
        if !game.runnerInstalled || !game.steamInstalled { return ("Set up needed", .orange) }
        if game.account == nil { return ("Sign in", .blue) }
        if !game.gameInstalled { return ("Not installed", .secondary) }
        return ("Ready", .green)
    }
}

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wineglass").font(.system(size: 52, weight: .thin)).foregroundStyle(.pink.gradient)
            Text("Choose a game").font(.title2.weight(.semibold))
            Text("Windows games, running on your Mac.").foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
    }
}
