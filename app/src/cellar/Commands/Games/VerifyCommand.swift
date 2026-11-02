import CellarDomain
import ArgumentParser
import CellarData
import Foundation

/// `cellar verify <slug>`: prove a game works, with nobody watching (#203).
///
/// Starts the game the way Play does, watches it, closes it, and writes a report with a PASS, FAIL
/// or COULD NOT CHECK for every baseline check. Exits 0 only when every check passed, so a script
/// (or an agent) can gate on it.
struct VerifyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Start a game, watch it and report whether it really works: signed in, online, stays up, closes cleanly.",
        discussion: """
            Runs the same baseline for every game: the store signed in by itself with no sign-in window, \
            Steam online, the game's own process reaching its servers with no TLS errors, no crash reporter \
            or Wine crash, and nothing left running afterwards. Closes the game and its store when it is done.

            The report is written to ~/Library/Application Support/Cellar/verify/<game>/<time>/ \
            (report.md and report.json). Exits 0 only when every check passed.
            """
    )

    @Argument(help: "Profile slug to verify, e.g. 'planet-coaster-2'.")
    var slug: String

    @Option(name: .long, help: "Cold launches in a row; every one has to pass.")
    var runs = 1

    @Option(name: .long, help: "How many minutes each launch has to stay up.")
    var minutes = 5.0

    @Flag(name: .long, help: "Print the report as JSON instead of Markdown.")
    var json = false

    func run() throws {
        // A reader that goes away (the app, an agent's pipe) must not stop the teardown halfway.
        signal(SIGPIPE, SIG_IGN)
        let plan = try Game.plan(slug: slug)
        var verify = VerifyGame(plan, runs: runs, surviveSeconds: Int(minutes * 60))
        // Ctrl-C (or a kill from whatever started us) stops verify the tidy way: the game, its
        // store and Wine are closed and the report keeps the runs that were done (#249).
        let stop = Stop()
        let sources = [SIGINT, SIGTERM].map { number -> DispatchSourceSignal in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                if stop.request() {
                    FileHandle.standardError.write(Data("\nStopping: closing the game and writing the report. Press Ctrl-C again to quit at once.\n".utf8))
                } else {
                    Foundation.exit(130)
                }
            }
            source.resume()
            return source
        }
        defer { sources.forEach { $0.cancel() } }
        verify.isInterrupted = { stop.requested }
        let (report, folder) = verify.run { print(Term.dim($0)) }

        print("")
        if json, let data = try? String(contentsOf: folder.appendingPathComponent("report.json"), encoding: .utf8) {
            print(data)
        } else {
            print(report.markdown)
        }
        print("Report: \(folder.path)")
        switch report.verdict {
        case .pass: print(Term.green("\(plan.name): every check passed."))
        case .fail: print(Term.red("\(plan.name): \(report.summary)"))
        case .couldNotCheck: print(Term.yellow("\(plan.name): \(report.summary)"))
        }
        if report.verdict != .pass { throw ExitCode(report.verdict == .fail ? 1 : 2) }
    }

    /// Whether a stop was asked for, readable from the verify loop while a signal handler sets it.
    final class Stop: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        /// Record a request. True for the first, which asks for a tidy stop.
        func request() -> Bool {
            lock.lock(); defer { lock.unlock() }
            count += 1
            return count == 1
        }

        var requested: Bool {
            lock.lock(); defer { lock.unlock() }
            return count > 0
        }
    }
}
