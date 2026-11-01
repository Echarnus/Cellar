import CellarDomain
import SwiftUI
import CellarUI

/// One game in the downloads panel: its store, its name, what it is doing, and the button that
/// stops it (running) or takes it out of the line (waiting).
struct DownloadRow: View {
    let name: String
    let store: GameStore
    let activity: GameActivity
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            StoreMark(store: store, size: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.caption.weight(.medium)).lineLimit(1)
                if case .working(let progress) = activity, let fraction = progress?.fraction {
                    ProgressView(value: fraction).controlSize(.mini).tint(store.tint)
                        .accessibilityHidden(true)
                }
                Text(activity.statusText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            .help(isRunning ? Text("Stop downloading \(name)") : Text("Take \(name) out of the queue"))
            .accessibilityLabel(isRunning ? Text("Stop downloading \(name)") : Text("Take \(name) out of the queue"))
        }
        .accessibilityElement(children: .contain)
    }

    private var isRunning: Bool {
        if case .working = activity { return true }
        return false
    }
}
