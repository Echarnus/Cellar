import Testing
import SwiftUI
import Foundation
import CellarKit
@testable import CellarUI

/// The install progress bar, drawn offscreen in every state it passes through.
///
/// The sheet lands in `.build/ui-snapshots/install-progress-{light,dark}.png` — open it instead of
/// starting a 2 GB download to see what the bar looks like.
@MainActor
@Suite("Install progress bar")
struct InstallProgressBarTests {

    private static let states: [(String, GameStore, InstallProgress?)] = [
        ("Planet Coaster 2", .steam, nil),
        ("Planet Coaster 2", .steam, InstallProgress(.runtime)),
        ("Planet Coaster 2", .steam, InstallProgress(.bottle)),
        ("Diablo IV", .battlenet, InstallProgress(.client)),
        ("Planet Coaster 2", .steam, InstallProgress(.clientUpdate, fraction: 0.16)),
        ("Planet Coaster 2", .steam, InstallProgress(.downloading, fraction: 0.42)),
        ("The Witcher 3", .gog, InstallProgress(.installing)),
        ("Planet Coaster 2", .steam, InstallProgress(.updateCheck)),
        ("Planet Coaster 2", .steam, InstallProgress(.updating, fraction: 0.07)),
    ]

    @Test("A measured phase shows its percentage; an unmeasured one shows none")
    func percentOnlyWhenMeasured() {
        #expect(InstallProgressBar(game: "G", store: .steam,
                                   progress: InstallProgress(.downloading, fraction: 0.426)).percent == "42%")
        #expect(InstallProgressBar(game: "G", store: .steam,
                                   progress: InstallProgress(.bottle)).percent.isEmpty,
                "a bottle being built has no denominator, so a number would be invented")
        // Never "100%" while the last bytes are still arriving.
        #expect(InstallProgressBar(game: "G", store: .steam,
                                   progress: InstallProgress(.downloading, fraction: 0.998)).percent == "99%")
    }

    @Test("Before the first phase arrives the bar still says something true")
    func waitingState() {
        let bar = InstallProgressBar(game: "G", store: .steam, progress: nil)
        #expect(bar.title == "Getting ready")
        #expect(bar.detail.hasSuffix("."))
    }

    @Test("draw every state, light and dark")
    func drawSheet() throws {
        for scheme in [ColorScheme.light, .dark] {
            let sheet = VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(Self.states.enumerated()), id: \.offset) { _, state in
                    InstallProgressBar(game: state.0, store: state.1, progress: state.2)
                }
            }
            .padding(20)
            .frame(width: 400, height: 540, alignment: .topLeading)
            .environment(\.colorScheme, scheme)

            let bitmap = Snapshot.render(sheet, size: CGSize(width: 400, height: 540), scale: 2,
                                         background: scheme == .dark ? Color(white: 0.13) : Color(white: 0.97))
            let data = try #require(bitmap.pngData())
            let url = ContactSheetTests.outputDirectory
                .appendingPathComponent("install-progress-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: url)
            print("install progress sheet → \(url.path)")
        }
    }
}
