import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Signing in to Steam with an account name and password (#278): the route for every player the
/// QR code can't serve — no Steam mobile app, Steam Guard by email, or Steam Guard turned off.
///
/// The prompts are DepotDownloader 3.4.0's and SteamKit 3.2's own words, copied from their source;
/// if a newer pin rewords one, these fail before a player meets a sign-in that hangs on a question
/// nobody sees.
struct SteamPasswordSignInTests {

    // MARK: - Reading DepotDownloader's questions

    @Test("Each question DepotDownloader asks is recognised, with no line ending after it",
          arguments: [
            (#"Enter account password for "kennethdc": "#, SteamPasswordSignIn.Prompt.password),
            ("STEAM GUARD! Please enter the auth code sent to the email at me.com: ",
             .emailCode(hint: "me.com")),
            ("Please enter the authentication code sent to your email address: ", .emailCode(hint: nil)),
            ("STEAM GUARD! Please enter your 2-factor auth code from your authenticator app: ",
             .authenticatorCode),
            ("Please enter your 2 factor auth code from your authenticator app: ", .authenticatorCode),
          ])
    func readsPrompts(_ text: String, _ expected: SteamPasswordSignIn.Prompt) {
        #expect(SteamPasswordSignIn.prompt(in: text) == expected)
    }

    @Test("Progress lines are not mistaken for questions")
    func ignoresProgress() {
        for line in ["Logging 'kennethdc' into Steam3...", "Connecting to Steam3... Done!",
                     "Got 12 licenses for account!", "STEAM GUARD! Use the Steam Mobile App to confirm your sign in...",
                     "Using Steam3 suggested CellID: 42"] {
            #expect(SteamPasswordSignIn.prompt(in: line) == nil, "\(line)")
        }
    }

    @Test("Steam's refusals become something the player can act on")
    func readsFailures() {
        #expect(SteamPasswordSignIn.failure(in:
            "Failed to authenticate with Steam: Authentication failed with result InvalidPassword.") == .wrongPassword)
        #expect(SteamPasswordSignIn.failure(in:
            "Failed to authenticate with Steam: Authentication failed with result RateLimitExceeded.") == .tooManyAttempts)
        #expect(SteamPasswordSignIn.failure(in: "Unable to login to Steam3: ServiceUnavailable") == .other("ServiceUnavailable"))
        #expect(SteamPasswordSignIn.failure(in: "Got 12 licenses for account!") == nil)
    }

    // MARK: - The conversation

    @Test("The password is given once; asked again, the sign-in stops as a wrong password")
    func passwordOnce() {
        var talk = SteamPasswordSignIn.Conversation(password: "hunter2")
        #expect(talk.answer(.password, askForCode: { _ in nil }) == "hunter2")
        #expect(talk.answer(.password, askForCode: { _ in nil }) == nil)
        #expect(talk.failure == .wrongPassword)
    }

    @Test("An emailed code is asked for, and a refused one is asked for again as a retry")
    func emailCodeAndRetry() {
        var talk = SteamPasswordSignIn.Conversation(password: "pw")
        var asked: [SteamSignInRequest] = []
        #expect(talk.answer(.emailCode(hint: "me.com"), askForCode: { asked.append($0); return " ab1 2c " }) == "ab12c")
        talk.read("The previous 2-factor auth code you have provided is incorrect.")
        #expect(talk.answer(.emailCode(hint: "me.com"), askForCode: { asked.append($0); return "XY-9Z1" }) == "XY9Z1")
        #expect(asked == [.emailCode(hint: "me.com", retry: false), .emailCode(hint: "me.com", retry: true)])
    }

    @Test("An authenticator code is asked for as one")
    func authenticatorCode() {
        var talk = SteamPasswordSignIn.Conversation(password: "pw")
        var asked: SteamSignInRequest?
        #expect(talk.answer(.authenticatorCode, askForCode: { asked = $0; return "F4K3C" }) == "F4K3C")
        #expect(asked == .authenticatorCode(retry: false))
    }

    @Test("No code from the player stops the sign-in, as a choice and not an error")
    func noCodeCancels() {
        var talk = SteamPasswordSignIn.Conversation(password: "pw")
        #expect(talk.answer(.emailCode(hint: nil), askForCode: { _ in "  " }) == nil)
        #expect(talk.failure == .cancelled)
    }

    @Test("An account without Steam Guard is never asked anything past its password")
    func noSteamGuard() {
        var talk = SteamPasswordSignIn.Conversation(password: "pw")
        #expect(talk.answer(.password, askForCode: { _ in Issue.record("asked for a code"); return nil }) == "pw")
        talk.read("Logging 'someone' into Steam3...")
        talk.read("Got 3 licenses for account!")
        #expect(talk.established)
        #expect(talk.failure == nil)
    }

    // MARK: - The CLI's sentences, which the app reads back

    @Test("Every code request survives the trip from the CLI to the app",
          arguments: [SteamSignInRequest.emailCode(hint: "me.com", retry: false),
                      .emailCode(hint: "me.com", retry: true), .emailCode(hint: nil, retry: false),
                      .authenticatorCode(retry: false), .authenticatorCode(retry: true)])
    func requestRoundTrip(_ request: SteamSignInRequest) {
        #expect(SteamSignInRequest(sentence: request.sentence) == request)
        #expect(SteamSignInRequest(sentence: "  " + request.sentence) == request)
        #expect(request.sentence.hasSuffix(":"))
    }

    @Test("Every failure survives the trip from the CLI to the app",
          arguments: [SteamPasswordSignIn.Failure.wrongPassword, .tooManyAttempts, .cancelled, .other("ServiceUnavailable")])
    func failureRoundTrip(_ failure: SteamPasswordSignIn.Failure) {
        #expect(SteamPasswordSignIn.Failure(sentence: failure.sentence) == failure)
    }

    @Test("The CLI's sentences are plain words: no tool names, no commands")
    func plainWords() {
        let sentences = [SteamSignInRequest.emailCode(hint: "me.com", retry: true).sentence,
                         SteamSignInRequest.authenticatorCode(retry: true).sentence]
            + [SteamPasswordSignIn.Failure.wrongPassword, .tooManyAttempts, .cancelled].map(\.sentence)
        for sentence in sentences {
            for word in ["DepotDownloader", "Steam3", "cellar ", "stdin", "token", "2FA"] {
                #expect(!sentence.contains(word), "\(sentence)")
            }
        }
    }

    @Test("Ordinary CLI lines are neither requests nor failures")
    func ordinaryLines() {
        for line in ["Signed in as kennethdc.", "  Got 3 licenses for account!", "Checking which games you own…"] {
            #expect(SteamSignInRequest(sentence: line) == nil)
            #expect(SteamPasswordSignIn.Failure(sentence: line) == nil)
        }
    }

    // MARK: - The password stays off the command line

    @Test("The password sign-in passes no password argument, and asks for codes instead of an app approval")
    func passwordNeverAnArgument() {
        let args = DepotTool.Credentials.password(username: "kennethdc").arguments
        #expect(args == ["-username", "kennethdc", "-remember-password", "-no-mobile"])
        #expect(!args.contains("-password") && !args.contains("-pass"))
        #expect(CellarCommand.steamPasswordSignIn.arguments == ["steam", "login", "--password"])
    }

    // MARK: - Talking to a process

    /// A stand-in for DepotDownloader that asks what it asks, the way it asks it: `printf` with no
    /// newline, then a read from stdin. It says "password ok" only if the password arrived on stdin.
    static let fakeTool = #"""
    printf 'Enter account password for "kennethdc": '
    read pw
    [ "$pw" = "hunter2" ] && echo "password ok"
    printf 'STEAM GUARD! Please enter the auth code sent to the email at me.com: '
    read code
    if [ "$code" != "AB12C" ]; then
      echo "The previous 2-factor auth code you have provided is incorrect."
      printf 'STEAM GUARD! Please enter the auth code sent to the email at me.com: '
      read code
    fi
    [ "$code" = "AB12C" ] && echo "Got 3 licenses for account!"
    sleep 30
    """#

    static func fake() -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", fakeTool]
        return p
    }

    @Test("Questions are answered on stdin, never shown, and the run stops once the session is up")
    func conversesOverStdin() throws {
        var talk = SteamPasswordSignIn.Conversation(password: "hunter2")
        var asked: [SteamSignInRequest] = []
        var shown: [String] = []
        var codes = ["WRONG", "AB12C"]
        let started = Date()
        let stopped = try DepotTool.converse(with: Self.fake(), answer: { prompt in
            talk.answer(prompt, askForCode: { asked.append($0); return codes.removeFirst() })
        }, output: { line in
            talk.read(line)
            shown.append(line)
        }, stopWhen: { talk.established })
        #expect(stopped, "the run ends at the licence list, not after the tool's own exit")
        #expect(Date().timeIntervalSince(started) < 20)
        #expect(shown.contains("password ok"))
        #expect(talk.established)
        #expect(asked == [.emailCode(hint: "me.com", retry: false), .emailCode(hint: "me.com", retry: true)])
        // The prompts are answered, not passed on: the password one names the account.
        #expect(!shown.contains { $0.contains("Enter account password") || $0.contains("kennethdc") })
        #expect(!shown.contains { $0.contains("hunter2") })
    }

    @Test("No answer ends the tool instead of leaving it waiting")
    func noAnswerEndsTheRun() throws {
        let p = Self.fake()
        let started = Date()
        let stopped = try DepotTool.converse(with: p, answer: { _ in nil }, output: { _ in })
        #expect(!stopped)
        #expect(!p.isRunning)
        #expect(Date().timeIntervalSince(started) < 20)
    }
}
