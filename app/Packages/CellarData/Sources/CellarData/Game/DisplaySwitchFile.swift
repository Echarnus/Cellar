import CellarDomain
import Foundation

/// The full screen or window choice, for a game that reads extra command-line switches from a file
/// of its own (`display_switch_file` in a profile).
///
/// Rockstar's games start through the Rockstar Games Launcher, which starts the game itself and
/// drops whatever Cellar put on the stub's command line. But GTA IV and GTA V also read
/// `commandline.txt` beside their exe, one switch per line — Rockstar's support page for GTA V lists
/// `-windowed` and `-fullscreen` and says to put them there — so the choice goes into that file and
/// reaches the game whoever starts it.
///
/// Cellar owns only the display switches in that file. Every other line the player or a mod wrote
/// stays as it was; `-windowed` and `-fullscreen` are taken out and the current choice put back, so
/// switching to Game's Choice really hands the decision back to the game. A file that would end up
/// empty and did not exist is never created.
public enum DisplaySwitchFile {
    /// The profile's file name, if it is a plain name: no folders, so it can only land beside the exe.
    public static func parse(_ value: String?) -> String? {
        guard let name = value?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
              !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else { return nil }
        return name
    }

    /// Where the file goes for this plan: beside the game's exe, if that is on disk.
    public static func url(for plan: GamePlan) -> URL? {
        guard let name = plan.displaySwitchFile, let exe = plan.directLaunchExe else { return nil }
        return exe.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Bring the file in line with the plan's choice. Does nothing for a game without a switch file.
    public static func apply(_ plan: GamePlan) {
        guard plan.canChooseDisplayMode, let url = url(for: plan) else { return }
        let existing = try? String(contentsOf: url, encoding: .utf8)
        let chosen = plan.performance.displayMode.arguments(engine: plan.facts.engine) ?? []
        let owned = DisplayMode.allSwitches(engine: plan.facts.engine).filter { $0.hasPrefix("-") }
        guard let text = rewrite(existing, owned: owned, chosen: chosen), text != existing else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            CellarLog.info(.launch, "\(url.lastPathComponent) now says \(chosen.isEmpty ? "nothing about the display" : chosen.joined(separator: " ")) "
                + "for \(plan.name).", subject: plan.slug)
        } catch {
            CellarLog.failure(.launch, "Couldn't write \(url.lastPathComponent) for \(plan.name)'s display choice",
                              error, subject: plan.slug)
        }
    }

    /// The file's new text: `existing` without any `owned` switch, then `chosen`, one per line. Nil
    /// when there is nothing to write and nothing there to change.
    static func rewrite(_ existing: String?, owned: Set<String>, chosen: [String]) -> String? {
        let ownedLower = Set(owned.map { $0.lowercased() })
        var lines: [String] = []
        for line in (existing ?? "").components(separatedBy: .newlines) {
            // A line can hold several switches; only the display ones are dropped from it.
            let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            let kept = words.filter { !ownedLower.contains($0.lowercased()) }
            if kept.count == words.count {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(line) }
            } else if !kept.isEmpty {
                lines.append(kept.joined(separator: " "))
            }
        }
        lines += chosen
        if lines.isEmpty { return existing == nil ? nil : "" }
        // Windows line endings: the file is the game's, read by a Windows program.
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
