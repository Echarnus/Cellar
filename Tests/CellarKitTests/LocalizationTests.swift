import Foundation
import Testing

/// The app's Dutch translation, checked against the SwiftUI source it translates.
///
/// SwiftUI looks a `Text("…")` literal up by its English text, so a translation is only as good as
/// the match between that text and the key in `Localizable.strings`: reword a button and its Dutch
/// silently falls back to English. These tests make that a failure instead, and they hold the line
/// the other way too: a new literal on one of the app's screens needs a Dutch entry.
@Suite("Localization")
struct LocalizationTests {

    static let localization = Repo.root.appendingPathComponent("Resources/Localization", isDirectory: true)
    static let appSources = Repo.root.appendingPathComponent("Sources/CellarApp", isDirectory: true)

    /// Names and the debug placeholder: the same in every language, so they are not in the table.
    static let untranslated: Set<String> = ["Cellar", "DepotDownloader", "Cellar GUI works"]

    static func table(_ language: String) throws -> [String: String] {
        let url = localization.appendingPathComponent("\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(plist as? [String: String], "\(language) must be a flat key = value table")
    }

    /// Every Swift file in the app, with multi-line literals' `\` continuations joined and their
    /// opening `"""` folded into a plain quote, so a long caption written over several lines reads
    /// as the one key SwiftUI looks up.
    static func appSource() throws -> String {
        let files = try FileManager.default
            .contentsOfDirectory(at: appSources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let joined = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        return joined
            .replacingOccurrences(of: #"\\\n[ \t]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\"\"\"\n[ \t]*"#, with: "\"", options: .regularExpression)
    }

    /// The single-line literals SwiftUI localizes: the first argument of these views, when it is a
    /// plain literal (no interpolation) that ends the argument, not one being concatenated to.
    static func localizableLiterals(in source: String) throws -> Set<String> {
        let regex = try NSRegularExpression(pattern:
            #"\b(?:Text|Button|Label|Toggle|Section|Picker|Link|LabeledContent|\.help)\(\s*"((?:[^"\\]|\\[^(])*)"\s*[,)]"#)
        let range = NSRange(source.startIndex..., in: source)
        return Set(regex.matches(in: source, range: range).compactMap { match in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
                .map { $0.replacingOccurrences(of: #"\""#, with: "\"") }
        }.filter { $0.contains(where: \.isLetter) })
    }

    static func placeholders(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[@dlfs]"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    @Test("Both tables parse, English stays empty, and Dutch has the app's screens in it")
    func tablesParse() throws {
        #expect(try Self.table("en").isEmpty, "English is the source language: its keys are the text")
        #expect(try Self.table("nl").count > 100)
    }

    @Test("Every Dutch key is still English text in the app, so none of them is dead")
    func everyKeyIsInTheSource() throws {
        let source = try Self.appSource()
        for key in try Self.table("nl").keys {
            // An interpolated literal's key has %@ where the source has \(…): match the text before it.
            let literal = key.components(separatedBy: "%@").first ?? key
            #expect(source.contains("\"" + literal.replacingOccurrences(of: "\"", with: #"\""#)),
                    "'\(key)' is in nl.lproj but no longer in Sources/CellarApp — reworded?")
        }
    }

    @Test("Every literal on the app's screens has a Dutch entry")
    func everyLiteralIsTranslated() throws {
        let dutch = try Self.table("nl")
        let missing = try Self.localizableLiterals(in: Self.appSource())
            .subtracting(Self.untranslated)
            .filter { dutch[$0] == nil }
        #expect(missing.isEmpty, "add these to Resources/Localization/nl.lproj: \(missing.sorted())")
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

    @Test("A concatenated or interpolated label is spotted as one key, not English fragments")
    func extractorReadsWholeLiterals() throws {
        let sample = """
        Text("One literal")
        Button("With \\"quotes\\" inside") { }
        Text("Joined, " + "so a String — never looked up")
        Label("Connected: \\(names)", systemImage: "x")
        """
        #expect(try Self.localizableLiterals(in: sample) == ["One literal", #"With "quotes" inside"#])
    }
}
