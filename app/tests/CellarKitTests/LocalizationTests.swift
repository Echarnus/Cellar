import Foundation
import Testing

/// The app's Dutch translation, checked against the source it translates.
///
/// SwiftUI and `String(localized:)` look a literal up by its English text, so a translation is only
/// as good as the match between that text and the key in `Localizable.strings`: reword a button and
/// its Dutch silently falls back to English. These tests make that a failure instead, and they hold
/// the line the other way too: a new literal in the app needs a Dutch entry.
@Suite("Localization")
struct LocalizationTests {

    static let localization = Repo.app.appendingPathComponent("Resources/Localization", isDirectory: true)
    /// The app, and the engine copy it shows: a game's next-step hint, launch and install steps,
    /// the library's verdicts. Engine copy is `String(localized:)` too; it resolves against
    /// `Bundle.main`, which is Cellar.app in the app and in the CLI bundled inside it.
    static let sourceDirectories = ["CellarApp", "CellarKit", "CellarDomain"]
        .map { Repo.source($0) }

    /// Names and the debug placeholder: the same in every language, so they are not in the table.
    static let untranslated: Set<String> = ["Cellar", "DepotDownloader", "Cellar GUI works"]

    static func table(_ language: String) throws -> [String: String] {
        let url = localization.appendingPathComponent("\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(plist as? [String: String], "\(language) must be a flat key = value table")
    }

    static func appSource() throws -> String {
        try sourceDirectories.flatMap { directory -> [URL] in
            let walk = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
            return (walk?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        }
        .sorted { $0.path < $1.path }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
    }

    /// The calls whose first string literal is looked up in the table.
    static let lookups = try! NSRegularExpression(pattern:
        #"\b(?:Text|Button|Label|Toggle|Section|Picker|Link|LabeledContent|help|accessibilityLabel|accessibilityValue|accessibilityHint)\(\s*(?=")|String\(localized:\s*(?=")"#)

    /// Every key the app will look up: the literal each lookup is handed, with interpolations as
    /// `%@`, and only when the literal is the whole argument — `"a" + b` is a `String`, which is
    /// shown verbatim and never looked up.
    static func keys(in source: String) -> Set<String> {
        let chars = Array(source.unicodeScalars)
        // NSRange counts UTF-16 units; the scanner walks scalars. Map one to the other once.
        var scalarAt = [Int]()
        for (index, scalar) in chars.enumerated() {
            for _ in 0..<UTF16.width(scalar) { scalarAt.append(index) }
        }
        scalarAt.append(chars.count)
        var found = Set<String>()
        for match in lookups.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            let start = scalarAt[match.range.location + match.range.length]
            guard let (key, end) = literal(chars, at: start) else { continue }
            var next = end
            while next < chars.count, chars[next] == " " || chars[next] == "\n" { next += 1 }
            guard next < chars.count, chars[next] == "," || chars[next] == ")" else { continue }
            if key.replacingOccurrences(of: "%@", with: "").contains(where: \.isLetter) { found.insert(key) }
        }
        return found
    }

    /// Reads the Swift string literal opening at `start`, the way the compiler builds its key.
    static func literal(_ c: [Unicode.Scalar], at start: Int) -> (String, Int)? {
        if start + 2 < c.count, c[start + 1] == "\"", c[start + 2] == "\"" { return multiline(c, at: start) }
        var out = "", i = start + 1
        while i < c.count {
            switch c[i] {
            case "\"": return (out, i + 1)
            case "\n": return nil
            case "\\":
                guard i + 1 < c.count else { return nil }
                if c[i + 1] == "(" {
                    i = skipInterpolation(c, from: i + 2)
                    out += "%@"
                    continue
                }
                switch c[i + 1] {
                case "n": out += "\n"
                case "t": out += "\t"
                default: out.unicodeScalars.append(c[i + 1])
                }
                i += 2
            default:
                out.unicodeScalars.append(c[i]); i += 1
            }
        }
        return nil
    }

    /// A `"""` literal: lines joined where they end in `\`, indentation stripped.
    static func multiline(_ c: [Unicode.Scalar], at start: Int) -> (String, Int)? {
        var i = start + 3, raw = ""
        while i + 2 < c.count, !(c[i] == "\"" && c[i + 1] == "\"" && c[i + 2] == "\"") {
            if c[i] == "\\", c[i + 1] == "(" {
                i = skipInterpolation(c, from: i + 2); raw += "%@"; continue
            }
            raw.unicodeScalars.append(c[i]); i += 1
        }
        let joined = raw.replacingOccurrences(of: #"\\\n[ \t]*"#, with: "", options: .regularExpression)
        let lines = joined.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.drop { $0 == " " || $0 == "\t" } }
            .filter { !$0.isEmpty }
        return (lines.joined(separator: "\n"), i + 3)
    }

    /// Past the `)` that closes an interpolation, stepping over strings nested inside it.
    static func skipInterpolation(_ c: [Unicode.Scalar], from start: Int) -> Int {
        var depth = 1, i = start
        while i < c.count, depth > 0 {
            switch c[i] {
            case "\"":
                i += 1
                while i < c.count, c[i] != "\"" { i += c[i] == "\\" ? 2 : 1 }
            case "(": depth += 1
            case ")": depth -= 1
            default: break
            }
            i += 1
        }
        return i
    }

    /// An `Int` interpolates as `%lld`, anything else as `%@`; the scanner cannot see types, so
    /// both sides are compared with every placeholder written the same way.
    static func normalized(_ key: String) -> String {
        key.replacingOccurrences(of: #"%(?:\d+\$)?(?:lld|ld|d|@)"#, with: "%@", options: .regularExpression)
    }

    static func placeholders(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|ld|d|lf|f|@)"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .sorted()
    }

    @Test("Both tables parse, English stays empty, and Dutch covers the app")
    func tablesParse() throws {
        #expect(try Self.table("en").isEmpty, "English is the source language: its keys are the text")
        #expect(try Self.table("nl").count > 200)
    }

    @Test("Every literal the app looks up has a Dutch entry")
    func everyLiteralIsTranslated() throws {
        let dutch = Set(try Self.table("nl").keys.map(Self.normalized))
        let missing = Self.keys(in: try Self.appSource())
            .subtracting(Self.untranslated)
            .filter { !dutch.contains($0) }
        #expect(missing.isEmpty, "add these to Resources/Localization/nl.lproj: \(missing.sorted())")
    }

    @Test("Every Dutch key is still looked up by the app, so none of them is dead")
    func everyKeyIsInTheSource() throws {
        let used = Self.keys(in: try Self.appSource())
        let dead = try Self.table("nl").keys.filter { !used.contains(Self.normalized($0)) }
        #expect(dead.isEmpty, "in nl.lproj but no longer in Sources — reworded? \(dead.sorted())")
    }

    @Test("A translation keeps its placeholders, and is not just the English again")
    func translationsAreWellFormed() throws {
        let dutch = try Self.table("nl")
        for (key, value) in dutch {
            #expect(Self.placeholders(key) == Self.placeholders(value), "'\(key)' changes its placeholders")
            #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty, "'\(key)' has an empty translation")
        }
        let copied = dutch.filter { $0.key == $0.value && $0.key.split(separator: " ").count > 3 }
        #expect(copied.isEmpty, "untranslated sentences: \(copied.keys.sorted())")
    }

    @Test("The scanner builds the keys the compiler builds")
    func scannerReadsKeysLikeTheCompiler() {
        let sample = #"""
        Text("One literal")
        Button("With \"quotes\" inside") { }
        Text("Joined, " + "so a String — never looked up")
        Label("Connected: \(pads.map(\.name).joined(separator: ", "))", systemImage: "x")
        alert.messageText = String(localized: "Uninstall \(game.name)?")
        Text("""
            One sentence \
            over two lines.
            """)
        """#
        #expect(Self.keys(in: sample) == [
            "One literal", #"With "quotes" inside"#, "Connected: %@", "Uninstall %@?",
            "One sentence over two lines.",
        ])
        #expect(Self.normalized("Step %lld of %lld") == "Step %@ of %@")
    }
}
