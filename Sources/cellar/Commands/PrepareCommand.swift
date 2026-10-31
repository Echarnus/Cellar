import CellarDomain
import ArgumentParser
import CellarKit

/// Fetch what every game shares, before the first game asks for it.
struct PrepareCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prepare",
        abstract: "Download the parts every game shares now, so your first game starts sooner.",
        discussion: """
        Fetches the Windows runtime (Wine, with Apple's D3DMetal), the game downloader, and — when a
        game you might play needs it — the Windows Steam client with its first update. A few
        gigabytes in all. Every game's setup would download these anyway; this does it ahead of time.

        The Cellar app runs this on its own the first time it opens. Anything already here is
        skipped, so running it again is safe. A game set up while this runs waits for it rather than
        downloading the same files twice.
        """)

    @Flag(name: .customLong("no-steam"), help: "Leave the Windows Steam client for later.")
    var noSteam = false

    @Flag(name: .long, help: "Only say what is still missing; download nothing.")
    var check = false

    func run() throws {
        let missing = Preparation.missing(includeSteam: !noSteam)
        if check {
            if missing.isEmpty {
                print(Term.green("Ready.") + " Everything every game shares is on this Mac.")
            } else {
                print(Term.bold("Still to download:"))
                for part in missing { print("  · \(part.title) " + Term.dim("(\(part.size))")) }
                print(Term.dim("Download them now with: cellar prepare"))
                throw ExitCode(1)
            }
            return
        }

        guard !missing.isEmpty else {
            print(Term.green("Ready.") + " Everything every game shares is already on this Mac.")
            return
        }
        print(Term.bold("Getting Cellar ready") + Term.dim("  — "
            + missing.map(\.title).joined(separator: ", ")))
        let failures = try Preparation.run(includeSteam: !noSteam) { print("  " + Term.dim($0)) }
        print("")
        if failures.isEmpty {
            print(Term.green("Ready.") + " Your first game will only need to download itself.")
        } else {
            print(Term.yellow("Partly ready.") + " These will be fetched when a game first needs them:")
            for (part, why) in failures { print("  · \(part.title): \(why)") }
            throw ExitCode(1)
        }
    }
}
