import Foundation
import Testing
import CellarDomain
@testable import CellarKit

/// The launch window's checklist, and the marker lines the app reads it from.
///
/// The app drives the `cellar` CLI and follows a launch through `LaunchMarker` lines on stdout, so
/// these two are a protocol between two programs: a stage that does not survive the trip is a
/// launch window stuck on its first step. The wording is held to skills/ux.md — the list a game
/// shows is the route it will really take, and every step is a sentence.
struct LaunchStageTests {

    @Test("A game that runs bare never shows a step for a client it does not open")
    func bareRoute() {
        let context = LaunchContext(game: "The Witcher 3", store: .gog, throughClient: false)
        let steps = LaunchStage.sequence(context)
        #expect(steps == [.preparing, .starting, .waiting])
        for stage in steps {
            let words = stage.title(context) + " " + stage.detail(context)
            #expect(!words.contains(GameStore.gog.displayName), "\(stage) mentions a client that is never opened")
        }
    }

    @Test("A client route opens the client first; signing in takes that step's place")
    func clientRoutes() {
        let steam = LaunchContext(game: "Planet Coaster 2", store: .steam, throughClient: true)
        #expect(LaunchStage.sequence(steam) == [.preparing, .client, .starting, .waiting])
        let signIn = LaunchContext(game: "Planet Coaster 2", store: .steam, throughClient: true, signsInFirst: true)
        #expect(LaunchStage.sequence(signIn) == [.preparing, .signIn, .starting, .waiting])
    }

    @Test("Outcomes are not steps: no route lists running, playing or closed")
    func outcomesAreNotSteps() {
        for store in GameStore.allCases {
            for throughClient in [true, false] {
                for signsIn in [true, false] {
                    let context = LaunchContext(game: "X", store: store, throughClient: throughClient, signsInFirst: signsIn)
                    let steps = LaunchStage.sequence(context)
                    #expect(steps.first == .preparing)
                    #expect(steps.last == .waiting)
                    #expect(!steps.contains(.running) && !steps.contains(.playing) && !steps.contains(.closed))
                }
            }
        }
    }

    @Test("Every stage has a title and a one-sentence detail, for every store and route",
          arguments: GameStore.allCases)
    func everyStageIsWorded(store: GameStore) {
        for throughClient in [true, false] {
            let context = LaunchContext(game: "Fixture Game", store: store, throughClient: throughClient)
            for stage in LaunchStage.allCases {
                #expect(!stage.title(context).isEmpty, "\(stage) has no title for \(store)")
                let detail = stage.detail(context)
                #expect(detail.hasSuffix("."), "\(stage) for \(store) is not a sentence: \(detail)")
                #expect(detail.first?.isUppercase == true, "\(stage) for \(store) starts mid-sentence: \(detail)")
            }
        }
    }

    @Test("Handing over the launch names the store only when a store is involved")
    func startingTellsTheTruth() {
        let viaSteam = LaunchContext(game: "Planet Coaster 2", store: .steam, throughClient: true)
        #expect(LaunchStage.starting.detail(viaSteam).contains("Steam"))
        let bare = LaunchContext(game: "Fallout Shelter", store: .steam, throughClient: false)
        #expect(!LaunchStage.starting.detail(bare).contains("Steam"))
        #expect(LaunchStage.starting.detail(bare).contains("Wine"))
    }

    @Test("Battle.net warns that its window may appear; Steam promises it will not")
    func clientWindowPromise() {
        let blizzard = LaunchContext(game: "Diablo IV", store: .battlenet, throughClient: true)
        #expect(LaunchStage.client.detail(blizzard).contains("window may appear"))
        let steam = LaunchContext(game: "Planet Coaster 2", store: .steam, throughClient: true)
        #expect(LaunchStage.client.detail(steam).contains("no window"))
    }

    // MARK: - The CLI → app protocol

    @Test("Every stage survives the trip through the CLI's marker line", arguments: LaunchStage.allCases)
    func markerRoundTrip(stage: LaunchStage) {
        let line = LaunchMarker.line(stage)
        #expect(LaunchMarker.stage(in: line) == stage)
        #expect(LaunchMarker.stage(in: "  \(line)\r\n") == stage, "a line read off a pipe keeps its newline")
        #expect(LaunchMarker.isMarker(line))
    }

    @Test("Ordinary output is never mistaken for a stage")
    func ordinaryOutput() {
        for line in ["Starting Steam quietly…", "", "running", "progress ::cellar-stage::running"] {
            #expect(LaunchMarker.stage(in: line) == nil, "\(line.debugDescription) read as a stage")
            #expect(!LaunchMarker.isMarker(line), "\(line.debugDescription) would be hidden from the player")
        }
    }

    @Test("A marker from a newer CLI is hidden from the player, but moves no stage")
    func unknownStage() {
        let line = LaunchMarker.prefix + "a-stage-this-build-does-not-know"
        #expect(LaunchMarker.isMarker(line))
        #expect(LaunchMarker.stage(in: line) == nil)
    }
}
