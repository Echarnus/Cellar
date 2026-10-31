import CellarDomain
import SwiftUI
import CellarKit
import CellarUI

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
        case .signedIn(let name):  return String(localized: "signed in as \(name)")
        case .signedInUnnamed:     return String(localized: "signed in")
        case .signedOut:           return String(localized: "not signed in")
        case .unknowable:          return String(localized: "sign-in state not published by this store")
        case .addedByYou:          return String(localized: "added by you, not verified by the store")
        case .notAdded:            return String(localized: "not added, so its games are not listed")
        }
    }
}
