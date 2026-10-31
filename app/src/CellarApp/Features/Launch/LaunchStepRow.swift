import CellarDomain
import AppKit
import SwiftUI
import CellarUI

/// One step of the launch: where it stands, what it is called, and — when it is the one happening —
/// what that actually means.
struct LaunchStepRow: View {
    enum State { case done, current, pending }

    let stage: LaunchStage
    let context: LaunchContext
    let state: State
    let detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            marker.frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(stage.title(context))
                    .font(.callout.weight(state == .current ? .semibold : .regular))
                    .foregroundStyle(state == .pending ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spokenState). \(stage.title(context)).\(detail.map { " " + $0 } ?? "")")
    }

    /// Mark and word, never colour alone (skills/ux.md): a ✓ for done, a spinner for the step in
    /// progress, an open circle for one not started.
    @ViewBuilder private var marker: some View {
        switch state {
        case .done:    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .current: ProgressView().controlSize(.small).scaleEffect(0.7)
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary).font(.caption)
        }
    }

    private var spokenState: String {
        switch state {
        case .done:    return String(localized: "Done")
        case .current: return String(localized: "In progress")
        case .pending: return String(localized: "Not started")
        }
    }
}
