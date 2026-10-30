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

    @Test("Reduce Motion holds the sweep still; otherwise it moves with the clock")
    func sweepRespectsReduceMotion() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let later = start.addingTimeInterval(0.35)
        #expect(Track.sweepPhase(at: start, reduceMotion: true) == 0.5)
        #expect(Track.sweepPhase(at: later, reduceMotion: true) == 0.5, "no motion at all, not slower motion")
        #expect(Track.sweepPhase(at: start, reduceMotion: false) != Track.sweepPhase(at: later, reduceMotion: false))
        for step in 0..<20 {
            let phase = Track.sweepPhase(at: start.addingTimeInterval(Double(step) * 0.17), reduceMotion: false)
            #expect(phase >= 0 && phase < 1)
        }
    }

    @Test("Increase Contrast gets a stronger empty track")
    func trackFollowsIncreaseContrast() {
        #expect(Track.trackOpacity(increasedContrast: true) > Track.trackOpacity(increasedContrast: false))
        #expect(Track.trackOpacity(increasedContrast: true) >= 0.25, "visible on its own against the window")
    }

    /// The track drawn for real, `width` points wide on white, in the light scheme.
    private static func renderTrack(fraction: Double?, increasedContrast: Bool = false,
                                    width: CGFloat = 300) -> Snapshot.Bitmap {
        Snapshot.render(Track(fraction: fraction, tint: Color(red: 1, green: 0, blue: 0))
                            .frame(width: width, height: 6)
                            .environment(\.colorScheme, .light)
                            .environment(\._colorSchemeContrast, increasedContrast ? .increased : .standard),
                        size: CGSize(width: width, height: 6), scale: 2, background: .white)
    }

    @Test("A measured bar fills its share, and the sweep stays out of it")
    func measuredBarFillsItsShare() {
        let bitmap = Self.renderTrack(fraction: 0.42)
        let row = bitmap.height / 2
        let tinted = (0..<bitmap.width).filter { x in
            let p = bitmap[x, row]
            return p.r > 0.8 && p.g < 0.3 && p.b < 0.3
        }
        let share = Double(tinted.count) / Double(bitmap.width)
        #expect(abs(share - 0.42) < 0.04, "filled \(share), expected about 42% and no sweep on top")
        #expect((tinted.first ?? .max) < bitmap.width / 20, "the fill starts at the leading edge")
    }

    @Test("Increase Contrast draws a darker empty track, on screen and not only in the number")
    func increasedContrastTrackIsDarker() {
        let standard = Self.renderTrack(fraction: 0)
        let increased = Self.renderTrack(fraction: 0, increasedContrast: true)
        let centre = (standard.width / 2, standard.height / 2)
        let a = standard[centre.0, centre.1].luminance
        let b = increased[centre.0, centre.1].luminance
        #expect(a < 0.97, "the standard track is visible at all (\(a))")
        #expect(b < a - 0.08, "increased \(b) vs standard \(a)")
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
