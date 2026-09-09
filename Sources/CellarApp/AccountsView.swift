import SwiftUI
import CellarKit
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
struct AccountsSection: View {
    @ObservedObject var runner: CellarRunner
    let state: StoreAccountState
    let refresh: () -> Void

    /// The Steam QR challenge as a module matrix, once DepotDownloader draws one. Steam rotates it
    /// every few seconds, so this is replaced as each redraw arrives.
    @State private var steamQRCode: [[Bool]]?
    @State private var steamQRReader = SteamQRCodeReader()
    @State private var gogSignInFailed: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            steamRow
            steamQRPanel
            steamClientNote
            gogRow
            battleNetRow
        }
    }

    // MARK: - Steam: one row, one action

    private var steamRow: some View {
        AccountRow(
            store: .steam,
            title: "Steam",
            state: steamState,
            detail: state.isLoaded ? state.steam.summary : "Checking…",
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
        guard state.isLoaded else { return "Sign in" }
        switch state.steam {
        case .signedIn:  return "Sign out"
        case .expired:   return "Sign in again"
        case .signedOut: return "Sign in"
        }
    }

    private func steamAction() {
        if case .signedIn = state.steam {
            runner.run(["steam", "login", "--forget"], title: "Signing out", then: {
                steamQRCode = nil
                refresh()
            })
            return
        }
        steamQRCode = nil
        steamQRReader = SteamQRCodeReader()
        runner.run(["steam", "login"], title: "Waiting for the QR scan", observe: { chunk in
            // DepotDownloader only *draws* the challenge, as terminal ASCII sized for a monospace
            // font — unscannable in a GUI. Read it back into modules and draw it properly. Steam
            // rotates the code, so later blocks replace it.
            for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
                if let matrix = steamQRReader.consume(String(line)) { steamQRCode = matrix }
            }
        }, then: {
            steamQRCode = nil       // the code is spent either way
            refresh()
        })
    }

    @ViewBuilder private var steamQRPanel: some View {
        if let steamQRCode {
            QRCodePanel(modules: steamQRCode)
        } else if runner.busy, runner.busyTitle == "Waiting for the QR scan" {
            // The gap between launching the tool and its first output is real; name it.
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Asking Steam for a sign-in code…").font(.callout).foregroundStyle(.secondary)
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
                    ? "Your whole GOG library — DRM-free, so nothing runs beside your game."
                    : "Opens GOG in a window. One sign-in covers every GOG game.",
                actionTitle: state.gogSignedIn ? "Sign out" : "Sign in",
                busy: runner.busy) {
                    if state.gogSignedIn {
                        runner.run(["gog", "logout"], title: "Signing out", then: { refresh() })
                    } else {
                        gogSignInFailed = nil
                        GOGSignInWindow.present { result in
                            switch result {
                            case .code(let code):
                                runner.run(["gog", "login", "--code", code],
                                           title: "Signing in to GOG", then: { refresh() })
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
                ? "Added by you, so Blizzard's games are in your library. Cellar can't check this one — you sign in inside Battle.net when it opens."
                : "Blizzard doesn't publish who is signed in, so Cellar has to ask. Add it and its games appear; you sign in inside Battle.net itself.",
            actionTitle: state.battleNetAdded ? "Remove" : "Add",
            busy: runner.busy) {
                runner.run(["battlenet", state.battleNetAdded ? "forget" : "add"],
                           title: state.battleNetAdded ? "Removing Battle.net" : "Adding Battle.net",
                           then: { refresh() })
            }
    }
}

/// A snapshot of every store's sign-in state, read once per refresh — never from a view body.
///
/// Reading disk in a view body would run `Game.summaries()` (which resolves game icons, spawning
/// tools) during view creation, on the main thread, in the middle of a window's first layout —
/// which is how this app has crashed in AttributeGraph before (skills/swift.md).
struct StoreAccountState {
    /// The one Steam sign-in, as CellarKit computed it. The view never derives this itself, so the
    /// app and `cellar accounts` cannot describe the same session differently.
    var steam: SteamAccount.State = .signedOut
    /// The account signed in to the *in-bottle Windows client*, when there is one. A fact about the
    /// machine, not an account row.
    var steamClientAccount: String?
    var gogSignedIn = false
    var gogAccount: String?
    /// Whether the player has told Cellar they have a Battle.net account. Not a sign-in: it is the
    /// only thing Cellar can know about Blizzard, and it decides whether its games are listed.
    var battleNetAdded = false
    /// False until the first read, so the UI never states something it hasn't checked yet.
    var isLoaded = false

    /// What Cellar knows before it has looked: nothing.
    static let unknown = StoreAccountState()

    static func current() -> StoreAccountState {
        StoreAccountState(
            steam: SteamAccount.state,
            steamClientAccount: SteamBottle.sharedLoggedInAccount,
            gogSignedIn: GOGAuth.isSignedIn,
            gogAccount: GOGAuth.cachedUsername,
            battleNetAdded: StoreLibrary.BattleNetAccount.isAdded,
            isLoaded: true)
    }
}

// MARK: - Pieces

enum AccountState {
    case signedIn(String)
    /// Signed in, but the store doesn't hand back a name worth showing.
    case signedInUnnamed
    case signedOut
    /// The store publishes nothing Cellar can read. Never a ✗ — see skills/ux.md.
    case unknowable
    /// The player said this store is theirs, and Cellar has no way to confirm it. Deliberately not
    /// drawn as a ✓: the mark and the word both say who is doing the claiming.
    case addedByYou
    /// Nothing published *and* nothing claimed — so this store's games are not listed yet.
    case notAdded
}

/// One store's sign-in state, as position + mark + word (never colour alone).
struct AccountRow: View {
    let store: GameStore
    let title: String
    let state: AccountState
    let detail: String
    /// nil means there is genuinely nothing Cellar can do from here.
    let actionTitle: String?
    let busy: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StoreMark(store: store, size: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    stateBadge
                }
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .disabled(busy)
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(accessibilityState). \(detail)")
    }

    @ViewBuilder private var stateBadge: some View {
        switch state {
        case .signedIn(let name):
            Label(name, systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium)).foregroundStyle(.green)
        case .signedInUnnamed:
            Label("Signed in", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium)).foregroundStyle(.green)
        case .signedOut:
            Label("Not signed in", systemImage: "circle.dashed")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        case .unknowable:
            Label("Not published", systemImage: "questionmark.circle")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        case .addedByYou:
            Label("Added by you", systemImage: "person.crop.circle.badge.questionmark")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        case .notAdded:
            Label("Not added", systemImage: "circle.dashed")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private var accessibilityState: String {
        switch state {
        case .signedIn(let name):  return "signed in as \(name)"
        case .signedInUnnamed:     return "signed in"
        case .signedOut:           return "not signed in"
        case .unknowable:          return "sign-in state not published by this store"
        case .addedByYou:          return "added by you, not verified by the store"
        case .notAdded:            return "not added, so its games are not listed"
        }
    }
}

/// Steam's QR challenge, drawn at a size a phone camera can actually read.
///
/// The modules come from `SteamQRCodeReader`, which reads back the code DepotDownloader draws in the
/// terminal. Rendered with `Canvas` — no library, no network, and crisp at any size because it is
/// rectangles rather than a scaled bitmap.
struct QRCodePanel: View {
    let modules: [[Bool]]

    /// Four modules of white margin, as the QR spec requires for reliable scanning.
    private let quietZone = 4

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Canvas { context, size in
                let count = modules.count + quietZone * 2
                guard count > 0 else { return }
                let module = min(size.width, size.height) / CGFloat(count)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                for (row, line) in modules.enumerated() {
                    for (column, dark) in line.enumerated() where dark {
                        let rect = CGRect(
                            x: CGFloat(column + quietZone) * module,
                            y: CGFloat(row + quietZone) * module,
                            // A hair of overlap, so seams between modules never show as light lines.
                            width: module + 0.5, height: module + 0.5)
                        context.fill(Path(rect), with: .color(.black))
                    }
                }
            }
            .frame(width: 164, height: 164)
            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel("Steam sign-in QR code")
            VStack(alignment: .leading, spacing: 6) {
                Text("Scan with the Steam mobile app").font(.headline)
                Text("Open Steam on your phone, tap the menu, then Scan QR code. Cellar never sees your password.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The code refreshes every few seconds — that's Steam, not a problem.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.leading, 34)
    }
}
