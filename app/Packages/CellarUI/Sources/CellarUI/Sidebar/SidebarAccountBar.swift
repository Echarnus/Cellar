import CellarDomain
import SwiftUI
import AppKit

/// The foot of the sidebar: who you are signed in as, and Settings.
///
/// This is where a Mac library puts the account — the App Store and Music both keep it at the
/// bottom of the sidebar, under the things you came for — and it replaces three unlabelled icons
/// that used to crowd the header beside the app's name. The account is a labelled button now,
/// because "am I signed in, and to what?" is a question the player should be able to answer
/// without hovering. Settings stays a small gear beside it for anyone who looks for one there;
/// ⌘, and the app menu remain the way in, as on every Mac.
///
/// Dumb on purpose: it is handed the summary and two actions, and decides nothing. It lives in
/// CellarUI rather than the app so `SidebarAccountBarTests` can draw it and look.
public struct SidebarAccountBar: View {
    let account: AccountSummary
    let openAccounts: () -> Void
    let openSettings: () -> Void

    @State private var hovering = false

    public init(account: AccountSummary, openAccounts: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.account = account
        self.openAccounts = openAccounts
        self.openSettings = openSettings
    }

    public var body: some View {
        HStack(spacing: 6) {
            Button(action: openAccounts) {
                HStack(spacing: 9) {
                    avatar
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.title)
                            .font(.callout.weight(account.tone == .loading ? .regular : .semibold))
                            .foregroundStyle(account.tone == .signedOut ? Color.accentColor
                                             : account.tone == .loading ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.tail)
                        if !account.detail.isEmpty {
                            Text(account.detail)
                                .font(.caption)
                                .foregroundStyle(account.tone == .needsAttention ? Color.orange : .secondary)
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6).padding(.vertical, 5)
                .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(account.tone == .loading)
            .onHover { hovering = $0 && account.tone != .loading }
            .help("Accounts — sign in to Steam, GOG and Battle.net (⌘⇧A)")
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens Accounts")

            Button(action: openSettings) {
                Image(systemName: "gearshape").font(.body)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.hoverBorderless)
            .foregroundStyle(.secondary)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    /// The account's own Steam picture when Cellar has it; otherwise a filled person once someone is
    /// signed in, an outlined one with a plus while nobody is, and a neutral placeholder while
    /// Cellar is still finding out. An orange badge marks a Steam sign-in that needs renewing, so the trouble
    /// shows before the words do.
    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            if account.tone == .loading {
                // A placeholder the shape of the avatar, as a Mac list shows before its content
                // arrives: neutral, so it can't be read as signed in or signed out.
                Circle().fill(.quaternary).frame(width: 24, height: 24)
            } else if let file = account.avatar, let picture = NSImage(contentsOf: file) {
                Image(nsImage: picture)
                    .resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: account.tone == .signedOut ? "person.crop.circle.badge.plus" : "person.crop.circle.fill")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(account.tone == .signedOut ? Color.accentColor : .secondary)
            }
            if account.tone == .needsAttention {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white, .orange)
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}
