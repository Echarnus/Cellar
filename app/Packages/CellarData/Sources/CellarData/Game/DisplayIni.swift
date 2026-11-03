import CellarDomain
import CoreGraphics
import Foundation

/// The full screen or window choice, for a game that keeps it in its own settings file rather than
/// on a command line (`display_ini` in a profile): Bethesda's Creation Engine, whose
/// `SkyrimPrefs.ini` / `Fallout4Prefs.ini` hold `[Display] bFull Screen`, `bBorderless`, `iSize W`
/// and `iSize H`.
///
/// Skyrim SE started in a 1518×962 window with a title bar on Kenneth's M5 (2026-11-03): the quality
/// preset Cellar copies as its first-run `SkyrimPrefs.ini` says windowed, at a size of its own. So:
///
/// - **Full screen** is a borderless window exactly the size of the Mac's main display. Under Wine
///   that is the reliable full screen: the Mac driver turns a borderless window covering the screen
///   into a full-screen one, while the game's exclusive mode would ask macOS to change display mode.
/// - **Window** is a bordered window at three quarters of the display, so it fits beside the Dock
///   and the menu bar and can be moved.
/// - **Game's Choice** leaves the file alone.
///
/// The size is the display as Windows sees it: points, or pixels when Retina resolution is on
/// (Wine's `RetinaMode`). Only those four keys are written; every other line stays as the game or
/// the player left it. A file that does not exist yet is not created — the game writes its own.
public enum DisplayIni {
    /// The profile's path, relative to the Windows user folder, if it stays inside it.
    public static func parse(_ value: String?) -> String? {
        guard let path = value?.trimmingCharacters(in: .whitespaces), !path.isEmpty,
              !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { return nil }
        return path
    }

    /// The engines whose settings file Cellar knows how to write.
    public static func supports(engine: String?) -> Bool {
        engine?.lowercased().hasPrefix("creation") == true
    }

    /// The four `[Display]` values for `mode` on a display of `screen` (width, height), or nil for
    /// Game's Choice.
    public static func values(for mode: DisplayMode, screen: (width: Int, height: Int)) -> [(String, String)]? {
        switch mode {
        case .game:
            return nil
        case .fullScreen:
            return [("bFull Screen", "0"), ("bBorderless", "1"),
                    ("iSize W", "\(screen.width)"), ("iSize H", "\(screen.height)")]
        case .window:
            // Even numbers: some renderers are unhappy with an odd back-buffer size.
            let width = screen.width * 3 / 4 / 2 * 2, height = screen.height * 3 / 4 / 2 * 2
            return [("bFull Screen", "0"), ("bBorderless", "0"),
                    ("iSize W", "\(width)"), ("iSize H", "\(height)")]
        }
    }

    /// `text` with each of `values` set under `[section]`: an existing line replaced in place (keys
    /// match without regard to case, as the game reads them), a missing one added at the end of the
    /// section, a missing section added at the end. Line endings follow the file's own.
    static func rewrite(_ text: String, section: String, values: [(String, String)]) -> String {
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: newline)
        if lines.last == "" { lines.removeLast() }
        let header = "[\(section.lowercased())]"
        var start: Int? = nil, end = lines.count
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard trimmed.hasPrefix("[") else { continue }
            if start != nil { end = index; break }
            if trimmed == header { start = index }
        }
        guard let start else {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("") }
            lines.append("[\(section)]")
            lines += values.map { "\($0.0)=\($0.1)" }
            return lines.joined(separator: newline) + newline
        }
        var missing: [String] = []
        for (key, value) in values {
            let line = lines[(start + 1)..<end].firstIndex { line in
                guard let eq = line.firstIndex(of: "=") else { return false }
                return line[..<eq].trimmingCharacters(in: .whitespaces).lowercased() == key.lowercased()
            }
            if let line { lines[line] = "\(key)=\(value)" } else { missing.append("\(key)=\(value)") }
        }
        // After the section's last non-blank line, so a blank line before the next section stays put.
        var insert = end
        while insert > start + 1, lines[insert - 1].trimmingCharacters(in: .whitespaces).isEmpty { insert -= 1 }
        lines.insert(contentsOf: missing, at: insert)
        return lines.joined(separator: newline) + newline
    }

    /// The Mac's main display as Windows will see it: points, or pixels with Retina resolution on.
    public static func mainDisplaySize(retina: Bool) -> (width: Int, height: Int)? {
        let display = CGMainDisplayID()
        if retina, let mode = CGDisplayCopyDisplayMode(display), mode.pixelWidth > 0 {
            return (mode.pixelWidth, mode.pixelHeight)
        }
        let bounds = CGDisplayBounds(display)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        return (Int(bounds.width), Int(bounds.height))
    }

    /// Bring the game's settings file in line with the plan's choice, before it starts.
    public static func apply(_ plan: GamePlan,
                             screen: (width: Int, height: Int)? = nil) {
        guard plan.canChooseDisplayMode, let path = plan.displayIni,
              supports(engine: plan.facts.engine) else { return }
        let url = FirstRunFiles.userFolder(of: plan).appendingPathComponent(path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let retina = plan.performance.value(.retina) == "true"
        guard let size = screen ?? mainDisplaySize(retina: retina),
              let values = values(for: plan.performance.displayMode, screen: size) else { return }
        let updated = rewrite(text, section: "Display", values: values)
        guard updated != text else { return }
        do {
            try updated.write(to: url, atomically: true, encoding: .utf8)
            CellarLog.info(.launch, "\(url.lastPathComponent) set to \(plan.performance.displayMode.rawValue) at "
                + "\(size.width)×\(size.height) for \(plan.name).", subject: plan.slug)
        } catch {
            CellarLog.failure(.launch, "Couldn't write \(url.lastPathComponent) for \(plan.name)'s display choice",
                              error, subject: plan.slug)
        }
    }
}
