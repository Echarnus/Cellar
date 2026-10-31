import CellarDomain
import Foundation

/// A bottle's `bottle.toml`: the player's own per-game settings, which no profile update touches.
public enum BottleConfig {
    public static func url(forBottle name: String) -> URL {
        Paths.prefixes.appendingPathComponent(name, isDirectory: true).appendingPathComponent("bottle.toml")
    }

    /// The bottle's scalar keys outside `[env]` and `[dll_overrides]`, whose keys are variable and
    /// DLL names, not settings. Inline ` #` comments are cut, as the profile scanner does — a
    /// hand-written `metal_validation = "false" # crash fixed?` must still count.
    public static func fields(_ url: URL) -> [String: String] {
        var dict: [String: String] = [:]
        for line in settingLines(readLines(url)) { dict[line.key] = line.value }
        return dict
    }

    public static func env(_ url: URL) -> [String: String] { ProfileStore.env(at: url) }

    /// Writes `key = "value"` in place of an existing line, or under `[performance]` (created at the
    /// end of the file if missing). Every other line, comment included, is left as it was.
    public static func set(_ setting: PerformanceSetting, to value: String, in url: URL) throws {
        try set(key: setting.key, to: try setting.normalise(value), section: "performance", in: url)
    }

    public static func unset(_ setting: PerformanceSetting, in url: URL) throws {
        try unset(key: setting.key, in: url)
    }

    /// Writes `key = "value"` in place of an existing line, or under `[section]` (created at the end
    /// of the file if missing). Every other line, comment included, is left as it was.
    static func set(key: String, to value: String, section: String, in url: URL) throws {
        let line = "\(key) = \"\(value)\""
        var lines = readLines(url)
        if let index = settingLines(lines).first(where: { $0.key == key })?.index {
            lines[index] = line
        } else if let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[\(section)]" }) {
            lines.insert(line, at: header + 1)
        } else {
            while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
            lines += lines.isEmpty ? ["[\(section)]", line] : ["", "[\(section)]", line]
        }
        try write(lines, to: url)
    }

    static func unset(key: String, in url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let lines = readLines(url)
        let drop = Set(settingLines(lines).filter { $0.key == key }.map(\.index))
        let kept = lines.indices.filter { !drop.contains($0) }.map { lines[$0] }
        guard kept.count != lines.count else { return }
        try write(kept, to: url)
    }

    /// `key = value` lines that can hold a setting, with their position: every section except
    /// `[env]` and `[dll_overrides]`. Quotes and a trailing ` #` comment are stripped from the value.
    private static func settingLines(_ lines: [String]) -> [(index: Int, key: String, value: String)] {
        var result: [(index: Int, key: String, value: String)] = []
        var inRawSection = false
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inRawSection = ["[env]", "[dll_overrides]"].contains(line); continue }
            guard !inRawSection, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            var value = String(line[line.index(after: eq)...])
            if let hash = value.range(of: " #") { value = String(value[..<hash.lowerBound]) }
            value = value.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            result.append((index, line[..<eq].trimmingCharacters(in: .whitespaces), value))
        }
        return result
    }

    private static func readLines(_ url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    private static func write(_ lines: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
