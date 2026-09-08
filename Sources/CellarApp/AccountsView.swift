import SwiftUI
import AppKit
import CellarKit

/// One window for "who am I signed in as" — the change that makes signing in a thing you do once.
///
/// Before this, sign-in was a per-game step: the library said "Sign in" on a game, you signed in
/// inside that bottle's Steam, and the next game asked again. Two things fixed that — one shared
/// Steam install behind every bottle, and stores whose token Cellar holds itself (GOG). Both are
/// account-level facts, so they get an account-level screen.
///
/// A separate `NSWindow`, never a `.sheet`: a sheet in the hosted view tree is a fatal
/// AttributeGraph cycle under `NSHostingView` (see skills/swift.md).
struct AccountsView: View {
    @StateObject private var runner = CellarRunner()
    let onClose: () -> Void

    /// What Cellar currently knows about each store. Held as explicit state and recomputed after
    /// every action, rather than re-read inside `body`: a view body must stay cheap and
    /// side-effect-free, and forcing a whole-tree rebuild (`.id(…)`) to refresh is exactly the
    /// pattern that provokes the AttributeGraph crash this app has a history of (skills/swift.md).
    /// Starts empty and is filled in `onAppear`. Reading disk in a property's default value would
    /// run `Game.summaries()` (which resolves game icons, spawning tools) during view creation, on
    /// the main thread, in the middle of the window's first layout.
    @State private var state = StoreAccountState.unknown
    /// The Steam QR challenge as a module matrix, once DepotDownloader draws one. Steam rotates it
    /// every few seconds, so this is replaced as each redraw arrives.
    @State private var steamQRCode: [[Bool]]?
    @State private var steamQRReader = SteamQRCodeReader()
    @State private var gogSignInFailed: String?
    /// The Steam Web API key being typed. Held here and cleared on save — it goes to the keychain,
    /// never to a view's persisted state.
    @State private var steamKeyDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    steamRow
                    steamBottleWarning
                    steamDownloadsRow
                    steamLibraryRow
                    gogRow
                    battleNetRow
                }
                .padding(16)
            }
            Divider()
            activity
            Divider()
            footer
        }
        // A *fixed* size, and the window is not resizable — same as Settings, which is the one
        // auxiliary window in this app that has never crashed. A flexible root frame inside
        // NSHostingView lets layout feed back into the view graph, and this app aborts in
        // AttributeGraph when that happens (skills/swift.md). Not worth being clever about.
        .frame(width: 560, height: 740)
        .background(.background)
        .onAppear(perform: refresh)
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Accounts").font(.title2.weight(.semibold))
            Text("Sign in once per store. Cellar shows only what it can actually check.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var footer: some View {
        HStack {
            if runner.busy {
                ProgressView().controlSize(.small)
                Text(runner.busyTitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done", action: onClose).keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    /// Always present, at a fixed height, rather than appearing when something happens: a pane that
    /// materialises mid-run changes the view tree's shape during layout, which is what this app
    /// crashes on. Empty, it explains itself.
    private var activity: some View {
        ScrollView {
            Text(runner.log.isEmpty ? "Anything Cellar runs shows up here." : runner.log)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(runner.log.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(height: 108)
        .background(Color.primary.opacity(0.04))
    }

    // MARK: - Rows

    /// Steam's client: one install behind every bottle, so one sign-in covers the library.
    private var steamRow: some View {
        let account = state.steamAccount
        return AccountRow(
            store: .steam,
            title: "Steam",
            state: account != nil ? .signedIn(account!) : .signedOut,
            detail: account != nil
                ? "Shared by every Steam game — one client, one sign-in."
                : "Opens the Windows Steam client. The QR code with the Steam mobile app is quickest.",
            actionTitle: account != nil ? "Open Steam" : "Sign in",
            busy: runner.busy) {
                guard let slug = state.steamBottleSlug else { return }
                runner.run(["steam", "open", slug], title: "Opening Steam", then: { changed() })
            }
    }

    /// Honesty: "Open Steam" needs a bottle to open Steam *in*, so when there is none, say so rather
    /// than leaving a control that quietly does nothing.
    @ViewBuilder private var steamBottleWarning: some View {
        if state.isLoaded && state.steamBottleSlug == nil {
            Text("Set up a Steam game first — the client lives in a bottle.")
                .font(.caption).foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 46)
        }
    }

    /// Steam's *download* session is a separate credential from the client's — a token, not a
    /// window — so it is its own row rather than a detail hidden inside the one above.
    private var steamDownloadsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            AccountRow(
                store: .steam,
                title: "Steam downloads",
                state: state.steamDownloadSession ? .signedInUnnamed : .signedOut,
                detail: state.steamDownloadSession
                    ? "Stored — downloads that skip the Windows client won't ask again."
                    : "Scan a QR code with the Steam mobile app. Cellar never sees your password.",
                actionTitle: state.steamDownloadSession ? "Sign out" : "Sign in with QR",
                busy: runner.busy) {
                    if state.steamDownloadSession {
                        runner.run(["steam", "login", "--forget"], title: "Signing out", then: {
                            steamQRCode = nil
                            changed()
                        })
                    } else {
                        steamQRCode = nil
                        steamQRReader = SteamQRCodeReader()
                        runner.run(["steam", "login"], title: "Waiting for the QR scan",
                                   observe: { chunk in
                            // DepotDownloader only *draws* the challenge, as terminal ASCII sized for
                            // a monospace font — unscannable in a GUI. Read it back into modules and
                            // draw it properly. Steam rotates the code, so later blocks replace it.
                            for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
                                if let matrix = steamQRReader.consume(String(line)) {
                                    steamQRCode = matrix
                                }
                            }
                        }, then: {
                            steamQRCode = nil       // the code is spent either way
                            changed()
                        })
                    }
                }

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
    }

    /// **Your Steam library** — the row that decides which Steam games the app may show you.
    ///
    /// Steam has no OAuth for entitlements, and an anonymous request for a library is refused unless
    /// the player's game details are public. A key issued to their own account answers either way.
    /// It is optional: without it Cellar still lists the Steam games it can see installed, and says
    /// so — it just will not pad the list with games it cannot confirm you own.
    private var steamLibraryRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            AccountRow(
                store: .steam,
                title: "Steam library",
                state: state.steamLibraryState,
                detail: state.steamLibraryDetail,
                actionTitle: state.steamHasKey ? "Forget key" : nil,
                busy: runner.busy) {
                    runner.run(["steam", "key", "--forget"], title: "Forgetting the key", then: { changed() })
                }

            if !state.steamHasKey {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste a Steam Web API key to list every Steam game you own.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        TextField("32-character key", text: $steamKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.callout, design: .monospaced))
                        Button("Save") {
                            runner.run(["steam", "key", "--set", steamKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)],
                                       title: "Reading your Steam library", then: {
                                steamKeyDraft = ""
                                changed()
                            })
                        }
                        .disabled(runner.busy || steamKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).count != 32)
                    }
                    Button("Get a key from Steam…") {
                        if let url = URL(string: SteamWebAPI.keyPage) { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.link).font(.callout)
                    Text("It's free and takes a minute. Cellar keeps it in your keychain and uses it only to read your own library.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 46)
            }
        }
    }

    /// GOG: the one store Cellar signs into itself, so it can name the account with a ✓.
    private var gogRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            AccountRow(
                store: .gog,
                title: "GOG",
                state: state.gogSignedIn
                    ? (state.gogAccount.map { AccountState.signedIn($0) } ?? .signedInUnnamed)
                    : .signedOut,
                detail: state.gogSignedIn
                    ? (state.gogLibrary.map { "\($0.totalCount) games in your library, and Cellar shows the ones it supports." }
                        ?? "Your whole GOG library — DRM-free, so nothing runs beside your game.")
                    : "Opens GOG in a window. One sign-in covers every GOG game.",
                actionTitle: state.gogSignedIn ? "Sign out" : "Sign in",
                busy: runner.busy) {
                    if state.gogSignedIn {
                        runner.run(["gog", "logout"], title: "Signing out", then: { changed() })
                    } else {
                        gogSignInFailed = nil
                        GOGSignInWindow.present { result in
                            switch result {
                            case .code(let code):
                                runner.run(["gog", "login", "--code", code], title: "Signing in to GOG", then: {
                                    changed()
                                })
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

    /// Battle.net: Blizzard publishes no readable signed-in state and no library, so this row never
    /// claims one — the ✓ stays off however this is answered.
    ///
    /// It does now carry a button, and the distinction is the whole point: it does not sign anyone
    /// in (that still happens inside Blizzard's own window, from the game's screen). It records that
    /// the player *has* an account, which is the only way a store that publishes nothing can have
    /// its games shown in a library that only shows games you own.
    private var battleNetRow: some View {
        AccountRow(
            store: .battlenet,
            title: "Battle.net",
            state: .unknowable,
            detail: state.battleNetConnected
                ? "Battle.net games are in your library. Cellar can't check which of them you own — Blizzard publishes nothing readable — so it doesn't claim to. Sign in inside the client, from a game's screen."
                : "Blizzard doesn't publish who is signed in or what you own, so Cellar can't check either. Tell it you have an account and its games appear in your library.",
            actionTitle: state.battleNetConnected ? "Remove" : "I have an account",
            busy: runner.busy) {
                runner.run(["battlenet", "connect"] + (state.battleNetConnected ? ["--forget"] : []),
                           title: state.battleNetConnected ? "Hiding Battle.net games" : "Connecting Battle.net",
                           then: { changed() })
            }
    }

    // MARK: - Behaviour

    /// Re-read every store's state, **off the main thread and after layout has finished**.
    ///
    /// This work is not cheap — it stats bottles, resolves game icons (which shells out), reads the
    /// keychain, and asks GOG for a username over the network. Doing it inline in `onAppear` meant
    /// blocking the main thread and then mutating `@State` in the middle of `NSHostingView`'s first
    /// layout pass, which re-enters the view graph and aborts in AttributeGraph. Hopping off and
    /// back keeps the window's first layout a plain, synchronous, side-effect-free pass.
    /// Re-read, and tell the library window that what it may show has changed. Every action in this
    /// window changes which games exist for this player, and the library is a separate view graph
    /// that would otherwise never find out.
    private func changed() {
        refresh()
        NotificationCenter.default.post(name: .cellarStoresChanged, object: nil)
    }

    private func refresh() {
        Task.detached {
            if GOGAuth.isSignedIn, GOGAuth.cachedUsername == nil {
                GOGAuth.cacheUsername(try? GOGAuth.username())
            }
            let snapshot = StoreAccountState.current()
            await MainActor.run { state = snapshot }
        }
    }
}

/// A snapshot of every store's sign-in state, read once per refresh — never from a view body.
struct StoreAccountState {
    var steamAccount: String?
    /// A Steam profile whose bottle is set up, so "Open Steam" has somewhere to open.
    var steamBottleSlug: String?
    var steamDownloadSession = false
    /// Whether a Steam Web API key is stored — the difference between "your library" and "the games
    /// Cellar happens to have seen".
    var steamHasKey = false
    /// The cached owned libraries, so this window can say how many games each store answered with.
    var steamLibrary: OwnedLibrary?
    var gogSignedIn = false
    var gogAccount: String?
    var gogLibrary: OwnedLibrary?
    /// Battle.net's connection is the player's word — see `BattleNetAccess`.
    var battleNetConnected = false
    /// False until the first read, so the UI never states something it hasn't checked yet.
    var isLoaded = false

    /// What Cellar knows before it has looked: nothing.
    static let unknown = StoreAccountState()

    static func current() -> StoreAccountState {
        StoreAccountState(
            steamAccount: SteamBottle.sharedLoggedInAccount,
            steamBottleSlug: Game.summaries()
                .first { $0.store == .steam && $0.runnerInstalled && $0.clientInstalled }?.slug,
            steamDownloadSession: DepotTool.hasStoredSession,
            steamHasKey: SteamWebAPI.hasKey,
            steamLibrary: StoreLibrary.cached(.steam),
            gogSignedIn: GOGAuth.isSignedIn,
            gogAccount: GOGAuth.cachedUsername,
            gogLibrary: StoreLibrary.cached(.gog),
            battleNetConnected: BattleNetAccess.isConnected,
            isLoaded: true)
    }

    /// The Steam library row's badge. A ✓ only for a library Steam actually handed over — a partial
    /// list read off the disk is not the same claim and must not look like one.
    var steamLibraryState: AccountState {
        guard let steamLibrary else { return .partial("Not read yet") }
        guard steamLibrary.isComplete else { return .partial("Installed games only") }
        return .signedIn("\(steamLibrary.totalCount) games")
    }

    var steamLibraryDetail: String {
        guard let steamLibrary else {
            return "Cellar hasn't read your Steam library yet."
        }
        return steamLibrary.isComplete
            ? "Read from \(steamLibrary.source). Cellar shows the ones it supports."
            : "Cellar can only confirm the \(steamLibrary.keys.count) game\(steamLibrary.keys.count == 1 ? "" : "s") already installed, so those are all it lists."
    }
}

// MARK: - Pieces

enum AccountState {
    case signedIn(String)
    /// Signed in, but the store doesn't hand back a name worth showing.
    case signedInUnnamed
    case signedOut
    /// Cellar has *part* of the answer and knows it is partial — the Steam library read off the
    /// disk rather than from Steam. Not a ✓, because it is not the whole truth; not "not signed
    /// in" either, because that is a different question and this row isn't asking it.
    case partial(String)
    /// The store publishes nothing Cellar can read. Never a ✗ — see skills/ux.md.
    case unknowable
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
        case .partial(let summary):
            Label(summary, systemImage: "circle.lefthalf.filled")
                .font(.caption.weight(.medium)).foregroundStyle(.orange)
        case .unknowable:
            Label("Not published", systemImage: "questionmark.circle")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private var accessibilityState: String {
        switch state {
        case .signedIn(let name):  return "signed in as \(name)"
        case .signedInUnnamed:     return "signed in"
        case .signedOut:           return "not signed in"
        case .partial(let summary): return summary
        case .unknowable:          return "sign-in state not published by this store"
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
