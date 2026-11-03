import CellarDomain
import SwiftUI
import CellarData
import CellarUI

/// The sign-in, and there is one of it.
///
/// Steam used to be asked for three times over: inside each bottle's Windows client, again for the
/// download session, and a third time for a Web API key so Cellar could list what you own. Three
/// prompts for one account is not a security boundary, it is a bug in the story. There is now a
/// single Steam sign-in — Steam's own QR device flow, run once — and it is what tells Cellar which
/// games you own and lets it download them. It lives in Settings, because that is where a person
/// looks for the account they signed in with.
///
/// The in-bottle Windows client is not a second account. It is a runtime dependency of the games
/// whose DRM talks to a running Steam, and it is reported as a fact about the machine — never as
/// another sign-in to perform.
struct AccountsView: View {
    let runner: ActivityStore
    let library: LibraryViewModel
    let state: StoreAccountState
    let refresh: () -> Void

    /// The Steam QR challenge as a module matrix, once DepotDownloader draws one. Steam rotates it
    /// every few seconds, so this is replaced as each redraw arrives.
    @State private var steamQRCode: [[Bool]]?
    @State private var steamQRReader = SteamQRCodeReader()
    /// What the sign-in is doing once the phone has approved. Replaces the code, which is spent.
    @State private var steamSignInProgress: String?
    @State private var gogSignInFailed: String?

    // The account-name-and-password sign-in, for players without the Steam mobile app.
    @State private var showsPasswordForm = false
    @State private var steamAccountName = ""
    /// Held only until it is handed to the sign-in, then cleared. Never logged, never saved.
    @State private var steamPassword = ""
    /// The Steam Guard code Steam is waiting for, while it waits.
    @State private var steamCodeRequest: SteamSignInRequest?
    @State private var steamCode = ""
    @State private var steamPasswordProblem: String?

    /// The QR sign-in's activity title, and how the panel knows that sign-in is the one running —
    /// one value, so the comparison holds in every language.
    private static let qrTitle = String(localized: "Waiting for the QR scan")
    /// The password sign-in's activity title, for the same reason.
    private static let passwordTitle = String(localized: "Signing in to Steam")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            steamRow
            steamQRPanel
            steamPasswordPanel
            steamClientNote
            // Hidden, not removed, while the first release is Steam only (`StoreAvailability`).
            if GameStore.gog.isOffered { gogRow }
            if GameStore.battlenet.isOffered { battleNetRow }
        }
    }

    /// Every sign-in, sign-out and add ends here. Accounts is its own window, so the library in the
    /// main window has to be *told* — without this a player who just signed in keeps looking at
    /// "Sign in to see your games" until they happen to press reload. It is the same `LibraryViewModel`
    /// the main window draws, so telling it is a call.
    private func accountsChanged() {
        refresh()
        library.accountsChanged()
    }

    // MARK: - Steam: one row, one action

    private var steamRow: some View {
        AccountRow(
            store: .steam,
            title: "Steam",
            state: steamState,
            detail: state.isLoaded ? state.steam.summary : String(localized: "Checking…"),
            actionTitle: steamActionTitle,
            busy: runner.busy,
            action: steamAction)
    }

    private var steamState: AccountState {
        switch state.steam {
        case .signedIn(let account, _, _): return .signedIn(account)
        // An expired session is *not* signed in. Drawing a ✓ for a credential Steam has already
        // refused is exactly the unverified tick this project refuses to draw.
        case .expired, .signedOut:         return .signedOut
        }
    }

    private var steamActionTitle: String {
        guard state.isLoaded else { return String(localized: "Sign in") }
        switch state.steam {
        case .signedIn:  return String(localized: "Sign out")
        case .expired:   return String(localized: "Sign in again")
        case .signedOut: return String(localized: "Sign in")
        }
    }

    private func steamAction() {
        if case .signedIn = state.steam {
            runner.run(.steamSignOut, title: String(localized: "Signing out"), then: {
                steamQRCode = nil
                accountsChanged()
            })
            return
        }
        steamQRCode = nil
        steamSignInProgress = nil
        steamQRReader = SteamQRCodeReader()
        showsPasswordForm = false
        runner.run(.steamSignIn, title: Self.qrTitle, observe: { line in
            // DepotDownloader only *draws* the challenge, as terminal ASCII sized for a monospace
            // font — unscannable in a GUI. Read it back into modules and draw it properly. Steam
            // rotates the code, so later blocks replace it.
            if let matrix = steamQRReader.consume(line) {
                if steamSignInProgress == nil { steamQRCode = matrix }
                return
            }
            follow(line)
        }, then: {
            steamQRCode = nil       // the code is spent either way
            steamSignInProgress = nil
            accountsChanged()
        })
    }

    /// Where either Steam sign-in has got to, from one line of the CLI's output.
    ///
    /// After the phone approves, the command still finishes the session and checks the library.
    /// Leaving the spent code up for that long reads as "the scan did nothing".
    private func follow(_ line: String) {
        switch SteamAccount.signInPhase(after: line) {
        case .approved?:
            steamQRCode = nil
            steamCodeRequest = nil
            if steamSignInProgress == nil { steamSignInProgress = String(localized: "Approved. Finishing sign-in…") }
        case .signedIn?:
            steamQRCode = nil
            steamCodeRequest = nil
            showsPasswordForm = false
            steamSignInProgress = String(localized: "Signed in. Checking which games you own…")
            accountsChanged()           // the row says so now, not after every game is checked
            // …and the library says it is checking, not "sign in", while the answers come in.
            library.beganChecking(String(localized: "Checking which games you own…"))
        case .checkingLibrary(let sentence)?:
            steamSignInProgress = sentence
            library.beganChecking(sentence)
        case nil:
            break
        }
    }

    // MARK: - Steam: account name and password

    /// Whether the Steam row is signed out, so another way in may be offered.
    private var steamNeedsSignIn: Bool {
        guard state.isLoaded else { return false }
        if case .signedIn = state.steam { return false }
        return true
    }

    private var passwordSignInRunning: Bool { runner.busy && runner.busyTitle == Self.passwordTitle }

    /// The second way in. The QR code stays the row's button — it is one scan and nothing to type —
    /// and this sits under it for everyone it can't serve: no Steam mobile app, Steam Guard by
    /// email, or no Steam Guard at all.
    @ViewBuilder private var steamPasswordPanel: some View {
        if steamNeedsSignIn || passwordSignInRunning {
            if showsPasswordForm || passwordSignInRunning {
                passwordForm
            } else if !(runner.busy && runner.busyTitle == Self.qrTitle) {
                Button("Sign In with Account Name and Password…") {
                    steamPasswordProblem = nil
                    showsPasswordForm = true
                }
                .buttonStyle(.hoverLink)
                .font(.callout)
                .disabled(runner.busy)
                .padding(.leading, 46)
            }
        }
    }

    private var passwordForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sign in with your account name and password").font(.headline)
            Text("For a Steam account without the Steam mobile app. If Steam emails you a code, or your account uses the Steam Guard authenticator, Cellar asks for the code next. Your password goes straight to Steam and is never stored.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let request = steamCodeRequest {
                Text(codeQuestion(request))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(String(localized: "Code"), text: $steamCode)
                    .textContentType(.oneTimeCode)
                    .onSubmit(sendSteamCode)
                    .accessibilityLabel(codeQuestion(request))
                HStack {
                    Button("Cancel") { runner.cancel() }
                        .buttonStyle(.hoverBordered)
                    Button("Continue", action: sendSteamCode)
                        .buttonStyle(.hoverProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(steamCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else if passwordSignInRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(steamSignInProgress ?? String(localized: "Signing in to Steam…"))
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                TextField(String(localized: "Account name"), text: $steamAccountName)
                    .textContentType(.username)
                SecureField(String(localized: "Password"), text: $steamPassword)
                    .textContentType(.password)
                    .onSubmit(startPasswordSignIn)
                if let steamPasswordProblem {
                    Text(steamPasswordProblem)
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Cancel") {
                        steamPassword = ""
                        steamPasswordProblem = nil
                        showsPasswordForm = false
                    }
                    .buttonStyle(.hoverBordered)
                    Button("Sign In", action: startPasswordSignIn)
                        .buttonStyle(.hoverProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canStartPasswordSignIn)
                }
            }
        }
        .frame(maxWidth: 380, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.leading, 34)
    }

    private var canStartPasswordSignIn: Bool {
        !runner.busy && !steamPassword.isEmpty
            && !steamAccountName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The question beside the code box, in the app's own words.
    private func codeQuestion(_ request: SteamSignInRequest) -> String {
        switch request {
        case .emailCode(let hint?, let retry):
            return retry
                ? String(localized: "That code didn't work. Enter the code from Steam's newest email to your address at \(hint).")
                : String(localized: "Steam emailed a sign-in code to your address at \(hint). Enter it here.")
        case .emailCode(nil, let retry):
            return retry
                ? String(localized: "That code didn't work. Enter the code from Steam's newest email.")
                : String(localized: "Steam emailed you a sign-in code. Enter it here.")
        case .authenticatorCode(let retry):
            return retry
                ? String(localized: "That code didn't work. The code changes every 30 seconds, so enter the one showing now.")
                : String(localized: "Open the Steam app on your phone and enter the Steam Guard code it shows.")
        }
    }

    /// What went wrong, in the app's own words.
    private func problem(_ failure: SteamPasswordSignIn.Failure) -> String? {
        switch failure {
        case .wrongPassword:
            return String(localized: "Steam didn't accept that account name and password. Check both and try again.")
        case .tooManyAttempts:
            return String(localized: "Steam has seen too many sign-in attempts. Wait a few minutes, then try again.")
        case .cancelled:
            return nil      // the player stopped it; that is an answer, not an error
        case .other:
            return String(localized: "Steam didn't sign you in. Try again in a moment.")
        }
    }

    private func startPasswordSignIn() {
        guard canStartPasswordSignIn else { return }
        let name = steamAccountName.trimmingCharacters(in: .whitespaces)
        let password = steamPassword
        steamPassword = ""          // handed over below; the form keeps no copy
        steamPasswordProblem = nil
        steamCodeRequest = nil
        steamCode = ""
        steamSignInProgress = nil
        // The name and the password go on the command's stdin, never in its arguments.
        runner.run(.steamPasswordSignIn, title: Self.passwordTitle, input: [name, password], observe: { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            if let request = SteamSignInRequest(sentence: text) {
                steamCode = ""
                steamCodeRequest = request
                return
            }
            if let failure = SteamPasswordSignIn.Failure(sentence: text) {
                steamCodeRequest = nil
                steamPasswordProblem = problem(failure)
                return
            }
            follow(line)
        }, then: {
            steamCodeRequest = nil
            steamCode = ""
            steamSignInProgress = nil
            accountsChanged()
        })
    }

    private func sendSteamCode() {
        let code = steamCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty, steamCodeRequest != nil else { return }
        steamCodeRequest = nil      // until Steam answers: accepted, or asked again
        steamCode = ""
        steamSignInProgress = String(localized: "Checking the code with Steam…")
        runner.reply(code)
    }

    @ViewBuilder private var steamQRPanel: some View {
        if let steamQRCode {
            QRCodePanel(modules: steamQRCode)
        } else if runner.busy, runner.busyTitle == Self.qrTitle {
            // The gap between launching the tool and its first output is real; name it. So is the
            // gap between approving on the phone and the command finishing.
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(steamSignInProgress ?? String(localized: "Asking Steam for a sign-in code…"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.leading, 46)
        }
    }

    /// Not a sign-in row. A game with Steamworks or Denuvo DRM talks to a *running* Steam client,
    /// which lives in the bottle and keeps its own session — so when there is one, say so plainly
    /// and leave it at that.
    @ViewBuilder private var steamClientNote: some View {
        if let account = state.steamClientAccount {
            Text("Windows Steam client: signed in as \(account), for games whose DRM needs it running.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 46)
        }
    }

    // MARK: - The other two stores

    /// GOG: the other store Cellar signs into itself, so it can name the account with a ✓.
    private var gogRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            AccountRow(
                store: .gog,
                title: "GOG",
                state: state.gogSignedIn
                    ? (state.gogAccount.map { AccountState.signedIn($0) } ?? .signedInUnnamed)
                    : .signedOut,
                detail: state.gogSignedIn
                    ? String(localized: "Your whole GOG library — DRM-free, so nothing runs beside your game.")
                    : String(localized: "Opens GOG in a window. One sign-in covers every GOG game."),
                actionTitle: state.gogSignedIn ? String(localized: "Sign out") : String(localized: "Sign in"),
                busy: runner.busy) {
                    if state.gogSignedIn {
                        runner.run(.gogSignOut, title: String(localized: "Signing out"), then: { accountsChanged() })
                    } else {
                        gogSignInFailed = nil
                        GOGSignInWindow.present { result in
                            switch result {
                            case .code(let code):
                                runner.run(.gogSignIn(code: code),
                                           title: String(localized: "Signing in to GOG"), then: { accountsChanged() })
                            case .cancelled:
                                break   // no error: closing the window is a legitimate answer
                            case .failed(let why):
                                gogSignInFailed = why
                            }
                        }
                    }
                }
            if let gogSignInFailed {
                Text(gogSignInFailed).font(.caption).foregroundStyle(.orange).padding(.leading, 46)
            }
        }
    }

    /// Battle.net: Blizzard publishes no readable signed-in state, so this row never claims one —
    /// but it does have to *ask*, because the library will not list a store nobody has connected,
    /// and asking is the only way Cellar can ever know this one. The button adds the account; it
    /// does not sign in, and the words are careful not to suggest otherwise. Signing in still
    /// happens inside Blizzard's client, the first time it opens.
    private var battleNetRow: some View {
        AccountRow(
            store: .battlenet,
            title: "Battle.net",
            state: state.battleNetAdded ? .addedByYou : .notAdded,
            detail: state.battleNetAdded
                ? String(localized: "Added by you, so Blizzard's games are in your library. Cellar can't check this one — you sign in inside Battle.net when it opens.")
                : String(localized: "Blizzard doesn't publish who is signed in, so Cellar has to ask. Add it and its games appear; you sign in inside Battle.net itself."),
            actionTitle: state.battleNetAdded ? String(localized: "Remove") : String(localized: "Add"),
            busy: runner.busy) {
                runner.run(state.battleNetAdded ? .battleNetForget : .battleNetAdd,
                           title: state.battleNetAdded ? String(localized: "Removing Battle.net") : String(localized: "Adding Battle.net"),
                           then: { accountsChanged() })
            }
    }
}
