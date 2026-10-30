import Foundation
import Testing
@testable import CellarKit

/// `ProcessWatch.superviseStart` is what survives D3DMetal's startup race: a game that fast-fails a
/// few seconds in is cleaned up and started again, and only one that stays up counts as launched.
/// Both store routes go through it, and nothing exercised it — a wrong answer here is either a
/// launch that gives up on a game that would have started, or a dead game reported as running.
///
/// The windows are a second each, so these run in seconds rather than the minutes a real launch takes.
struct StartSupervisorTests {

    @Test("A start that never appears, then one that dies while settling, is retried until one stays up")
    func retriesThroughTheRace() throws {
        var attempt = 0
        var cleanups = 0
        var checks = 0
        var stages: [LaunchStage] = []
        var lines: [String] = []

        try ProcessWatch.superviseStart(
            attempts: 3, appearSeconds: 1, settleSeconds: 1, backoffSeconds: 0,
            cleanup: { cleanups += 1 },
            start: { attempt += 1; checks = 0 },
            isUp: {
                checks += 1
                switch attempt {
                case 1: return false            // never appears
                case 2: return checks == 1      // appears, then dies inside the settle window
                default: return true            // stays up
                }
            },
            progress: { lines.append($0) },
            stage: { stages.append($0) })

        #expect(attempt == 3)
        #expect(cleanups == 3, "every attempt starts from a clean bottle, the first one included")
        // A retry goes back to "starting", which is what makes the second try visible, not a stall.
        #expect(stages == [.starting, .waiting, .starting, .waiting, .starting, .waiting])
        #expect(lines.contains { $0.contains("didn't start") })
        #expect(lines.contains { $0.contains("startup race") })
        #expect(lines.contains { $0.contains("Up after 3 attempts") })
    }

    @Test("A game that stays up on the first try is started once and reports nothing to retry")
    func firstTimeLucky() throws {
        var starts = 0
        var lines: [String] = []
        try ProcessWatch.superviseStart(attempts: 3, appearSeconds: 1, settleSeconds: 1, backoffSeconds: 0,
                                        cleanup: {}, start: { starts += 1 }, isUp: { true },
                                        progress: { lines.append($0) })
        #expect(starts == 1)
        #expect(lines.isEmpty, "a clean start has nothing to tell the player")
    }

    @Test("A game that never stays up is a failure after the last attempt, never a launch")
    func givesUpAndSaysSo() {
        var starts = 0
        do {
            try ProcessWatch.superviseStart(attempts: 2, appearSeconds: 1, settleSeconds: 1, backoffSeconds: 0,
                                            cleanup: {}, start: { starts += 1 }, isUp: { false })
            Issue.record("a game that never came up was reported as launched")
        } catch let error as CellarError {
            #expect(error.description.contains("2 attempts"), "the message says how hard Cellar tried")
            #expect(error.description.contains("Try launching again"), "and what the player can do")
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(starts == 2)
    }

    @Test("A start that throws stops the supervision at once rather than retrying a broken command")
    func aFailingStartIsNotRetried() {
        var starts = 0
        do {
            try ProcessWatch.superviseStart(attempts: 3, appearSeconds: 1, settleSeconds: 1, backoffSeconds: 0,
                                            cleanup: {},
                                            start: { starts += 1; throw CellarError.ioFailure("no client") },
                                            isUp: { true })
            Issue.record("a start that threw was reported as launched")
        } catch {
            #expect("\(error)".contains("no client"))
        }
        #expect(starts == 1)
    }
}
