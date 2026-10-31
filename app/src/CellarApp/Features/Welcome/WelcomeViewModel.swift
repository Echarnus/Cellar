import Foundation
import Observation
import CellarKit

/// The first-run folder ask: what macOS answered for each folder, which one it is asking about now,
/// and whether the walk is done.
///
/// `WelcomeView` owns one. Each macOS dialog blocks until the player answers it, so the walk runs
/// off the main thread and only its answers come back here.
@MainActor
@Observable
final class WelcomeViewModel {
    private(set) var answers: [HomeFolder: HomeFolderAccess.Access] = [:]
    private(set) var asking: HomeFolder?
    private(set) var finished = false

    /// The folders the player said no to, which the footer offers to change in System Settings.
    var deniedFolders: [HomeFolder] {
        HomeFolder.allCases.filter { answers[$0] == .denied }
    }

    /// Re-opened from Settings: the folders were already answered, so reading them cannot put a
    /// dialog on screen. Still off the main thread, because it touches the disk.
    func loadAnswers() {
        Task.detached(priority: .userInitiated) {
            let current = HomeFolderAccess.statuses()
            await MainActor.run {
                self.answers = current
                self.finished = true
            }
        }
    }

    /// Walk the folders one at a time, marking the row each dialog is waiting on.
    func ask() {
        Task.detached(priority: .userInitiated) {
            for folder in HomeFolder.allCases {
                await MainActor.run { self.asking = folder }
                let access = HomeFolderAccess.request(folder)
                await MainActor.run {
                    self.answers[folder] = access
                    self.asking = nil
                }
            }
            HomeFolderAccess.hasAsked = true
            await MainActor.run { self.finished = true }
        }
    }
}
