import SwiftUI
import AppKit
import CellarKit

/// First run: ask for the folders every Windows game needs, once, having said what they are for.
///
/// Without this the player meets macOS's *"Cellar.app would like to access files in your Documents
/// folder"* halfway through installing a game — no context, no idea whether saying no breaks
/// anything, and it arrives while a progress bar is running. The same three dialogs shown here are
/// the same three macOS would have shown; the difference is that they arrive together, at a moment
/// nothing is at stake, under a sentence explaining them.
///
/// A separate `NSWindow`, never a `.sheet`, and a fixed frame in a non-resizable window: a sheet in
/// the hosted view tree is a fatal AttributeGraph cycle under `NSHostingView` (skills/swift.md).
struct WelcomeView: View {
    /// Re-opened from Settings, the screen is a status board rather than an ask — the decision has
    /// already been made and macOS will not ask twice.
    let isReview: Bool
    let onClose: () -> Void

    @State private var answers: [HomeFolder: HomeFolderAccess.Access] = [:]
    @State private var asking: HomeFolder?
    @State private var finished = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 8) {
                ForEach(HomeFolder.allCases, id: \.self, content: row)
            }
            .padding(16)
            Spacer(minLength: 0)
            Divider()
            footer
        }
        // Fixed, and the window is not resizable — same as Settings and Accounts. A flexible root
        // frame inside NSHostingView lets layout feed back into the view graph, and this app aborts
        // in AttributeGraph when it does (skills/swift.md).
        .frame(width: 520, height: 430)
        .background(.background)
        .onAppear {
            guard isReview else { return }
            // Already answered, so reading the answers cannot put a dialog on screen. Still off the
            // main thread: it touches the disk.
            DispatchQueue.global(qos: .userInitiated).async {
                let current = HomeFolderAccess.statuses()
                DispatchQueue.main.async { answers = current; finished = true }
            }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "wineglass.fill").foregroundStyle(.pink)
                Text(isReview ? "Folder access" : "Welcome to Cellar")
                    .font(.title2.weight(.semibold))
            }
            Text(headline)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var headline: String {
        if isReview {
            return "What macOS currently lets Cellar reach. Windows games save into these folders, so a game whose folder is off keeps its saves inside its bottle instead."
        }
        if finished {
            return deniedFolders.isEmpty
                ? "That is everything Cellar needs. No further permission prompts while you are installing or playing."
                : "Cellar will not ask again. The folders you turned down stay off, and games use their bottle instead."
        }
        return "Cellar runs Windows games, and Windows games save into your Documents, Desktop and Downloads folders. macOS will ask about all three now — so it does not interrupt you halfway through installing a game."
    }

    private func row(_ folder: HomeFolder) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: folder.symbolName)
                .font(.system(size: 15))
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.displayName).font(.callout.weight(.medium))
                Text(folder.reason).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            state(folder)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.35)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folder.displayName): \(accessibilityState(folder)). \(folder.reason)")
    }

    /// Mark **and** word, never colour alone — and never a mark for something not yet asked.
    @ViewBuilder
    private func state(_ folder: HomeFolder) -> some View {
        if asking == folder {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Asking…").font(.caption).foregroundStyle(.secondary)
            }
        } else if let access = answers[folder] {
            HStack(spacing: 5) {
                Image(systemName: access == .granted ? "checkmark.circle.fill" : "slash.circle")
                    .foregroundStyle(access == .granted ? Color.green : Color.secondary)
                Text(access == .granted ? "Allowed" : "Off")
                    .font(.caption).foregroundStyle(access == .granted ? .primary : .secondary)
            }
        } else {
            HStack(spacing: 5) {
                Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
                Text("Not asked yet").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func accessibilityState(_ folder: HomeFolder) -> String {
        if asking == folder { return "asking" }
        guard let access = answers[folder] else { return "not asked yet" }
        return access == .granted ? "allowed" : "off"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if finished && !deniedFolders.isEmpty {
                Text(deniedSentence)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if finished && !deniedFolders.isEmpty {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(HomeFolderAccess.systemSettingsURL)
                    }
                }
                Spacer()
                if finished || isReview {
                    Button(isReview ? "Done" : "Start playing", action: onClose)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Not now", action: skip)
                    Button("Continue", action: ask)
                        .keyboardShortcut(.defaultAction)
                        .disabled(asking != nil)
                }
            }
        }
        .padding(16)
    }

    private var deniedSentence: String {
        let names = deniedFolders.map(\.displayName)
        let list = names.count == 1 ? names[0]
            : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        return "Games that would have used \(list) keep those files inside their bottle, so nothing breaks — "
            + "but a save will not show up in Finder where you would expect it. You can turn "
            + "\(names.count == 1 ? "it" : "them") on later in System Settings → Privacy & Security → Files and Folders."
    }

    private var deniedFolders: [HomeFolder] {
        HomeFolder.allCases.filter { answers[$0] == .denied }
    }

    // MARK: - Actions

    /// Walk the folders one at a time. Each call blocks until the player answers that dialog, so it
    /// runs off the main thread and the row it is waiting on is marked while it does.
    private func ask() {
        DispatchQueue.global(qos: .userInitiated).async {
            for folder in HomeFolder.allCases {
                DispatchQueue.main.async { asking = folder }
                let access = HomeFolderAccess.request(folder)
                DispatchQueue.main.async { answers[folder] = access; asking = nil }
            }
            HomeFolderAccess.hasAsked = true
            DispatchQueue.main.async { finished = true }
        }
    }

    /// "Not now" leaves macOS to ask on its own later — so the flag stays unset and the next launch
    /// offers this screen again. Nothing is claimed about folders that were never asked about.
    private func skip() { onClose() }
}
