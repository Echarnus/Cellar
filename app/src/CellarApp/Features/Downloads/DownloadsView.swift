import CellarDomain
import SwiftUI

/// The downloads queue, at the foot of the sidebar: the game downloading now and the ones waiting,
/// each with a way to stop it or take it out. Nothing at all while there is nothing to show.
struct DownloadsView: View {
    let downloads: DownloadsViewModel

    var body: some View {
        if !downloads.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Downloads").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .kerning(0.5).textCase(.uppercase)
                    Spacer()
                    if downloads.queue.count > 0 {
                        Text(downloads.queue.count == 1 ? String(localized: "1 waiting")
                             : String(localized: "\(downloads.queue.count) waiting"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let running = downloads.running {
                    DownloadRow(name: running.entry.name, store: running.entry.store,
                                activity: running.activity,
                                onCancel: { downloads.cancel(running.entry.slug) })
                }
                if let waitingOn = downloads.waitingOn {
                    // The line only moves when the runner is free; say what it is waiting for, or a
                    // queue that never starts reads as broken.
                    Text("Starts after: \(waitingOn)")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                ForEach(downloads.queue.waiting) { entry in
                    DownloadRow(name: entry.name, store: entry.store,
                                activity: .queued(position: downloads.queue.position(of: entry.slug) ?? 1),
                                onCancel: { downloads.cancel(entry.slug) })
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }
}
