import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// The versioned JSON lines `--events` prints and the app reads: what they look like on the wire,
/// that they round-trip, and that the older markers are still understood.
@Suite
struct CommandEventTests {

    @Test("A stage is one JSON line with its version and type", arguments: LaunchStage.allCases)
    func stageLine(_ stage: LaunchStage) {
        let line = CommandEvent.stage(stage).line
        #expect(line == #"{"stage":"\#(stage.rawValue)","type":"stage","v":1}"#)
        #expect(!line.contains("\n"), "one event, one line")
        #expect(CommandEvent.parse(line) == .stage(stage))
    }

    @Test("Install progress round-trips with and without a fraction", arguments: InstallPhase.allCases)
    func progressRoundTrip(_ phase: InstallPhase) {
        for progress in [InstallProgress(phase), InstallProgress(phase, fraction: 0.5)] {
            #expect(CommandEvent.parse(CommandEvent.install(progress).line) == .install(progress))
        }
    }

    @Test("The older markers still read as the same events, so app and CLI can be a version apart")
    func legacyMarkers() {
        #expect(CommandEvent.parse(LaunchMarker.line(.starting)) == .stage(.starting))
        let progress = InstallProgress(.downloading, fraction: 0.25)
        #expect(CommandEvent.parse(InstallMarker.line(progress)) == .install(progress))
    }

    @Test("A sentence for the player is never mistaken for an event")
    func prose() {
        for line in ["  Launching Diablo IV via Battle.net…", "", "{not json", "Downloaded to /tmp/x"] {
            #expect(CommandEvent.parse(line) == nil)
            #expect(!CommandEvent.isEvent(line))
        }
    }

    @Test("An event from a newer CLI is hidden from the player, not shown as JSON")
    func newerVersion() {
        let future = #"{"stage":"starting","type":"stage","v":2}"#
        let unknownType = #"{"type":"achievement","v":1}"#
        #expect(CommandEvent.parse(future) == nil, "a version this app can't read is not guessed at")
        #expect(CommandEvent.isEvent(future))
        #expect(CommandEvent.parse(unknownType) == nil)
        #expect(CommandEvent.isEvent(unknownType))
    }

    @Test("A field this version doesn't know is ignored rather than refused")
    func extraField() {
        let line = #"{"stage":"running","type":"stage","v":1,"pid":4242}"#
        #expect(CommandEvent.parse(line) == .stage(.running))
    }

    @Test("Only install and launch events go on the wire; sentences stay prose")
    func fromGameEvent() {
        #expect(CommandEvent(GameEvent.launch(.client)) == .stage(.client))
        #expect(CommandEvent(GameEvent.install(InstallProgress(.bottle))) == .install(InstallProgress(.bottle)))
        #expect(CommandEvent(GameEvent.step("hello")) == nil)
    }
}
