import Foundation
import Testing

/// Tier A: the translations reach a built app and macOS picks the right one.
///
/// SwiftUI reads a literal's translation from `Bundle.main`, so what matters is the bundle the
/// install scripts assemble, not the files in the repo. This builds that bundle with the scripts' own
/// copy command and Info.plist, opens it as macOS would, and asks it for Dutch and for a language
/// Cellar doesn't ship.
@Suite("Localization in the app bundle")
struct LocalizationBundleTests {

    static let scripts = ["Scripts/install-app.sh", "Scripts/package.sh"]

    static func script(_ path: String) throws -> String {
        try String(contentsOf: IT.packageRoot.appendingPathComponent(path), encoding: .utf8)
    }

    /// The script's own Info.plist heredoc, with its shell variables filled the way a build would.
    static func infoPlist(from script: String) throws -> String {
        let start = try #require(script.range(of: "<<PLIST\n"))
        let end = try #require(script.range(of: "\nPLIST\n", range: start.upperBound..<script.endIndex))
        return String(script[start.upperBound..<end.lowerBound])
            .replacingOccurrences(of: "$VERSION", with: "0.0.0-it")
            .replacingOccurrences(of: "$ICON_KEY", with: "")
            .replacingOccurrences(of: "$UPDATE_KEYS", with: "")
    }

    /// Assemble `Cellar.app` in scratch: the Info.plist and the translation copy, both taken from
    /// `path` and run as written.
    static func assembleApp(with path: String) throws -> URL {
        let text = try script(path)
        let app = IT.scratch("l10n").appendingPathComponent("Cellar.app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try infoPlist(from: text).write(to: app.appendingPathComponent("Contents/Info.plist"),
                                        atomically: true, encoding: .utf8)

        let copy = try #require(text.split(separator: "\n").first { $0.contains("Localization/*.lproj") },
                                "\(path) must copy the translations into the bundle")
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-eu", "-c", String(copy)]
        sh.currentDirectoryURL = IT.packageRoot
        sh.environment = ["APP": app.path, "PATH": "/usr/bin:/bin"]
        try sh.run()
        sh.waitUntilExit()
        #expect(sh.terminationStatus == 0, "\(path): `\(copy)` failed")
        return app
    }

    @Test("The bundle each script builds lists English and Dutch, with English as the fallback",
          arguments: scripts)
    func bundleDeclaresItsLanguages(path: String) throws {
        let bundle = try #require(Bundle(url: try Self.assembleApp(with: path)))
        #expect(bundle.developmentLocalization == "en")
        #expect(Set(bundle.localizations).isSuperset(of: ["en", "nl"]))
        #expect(Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: ["nl-BE"]).first == "nl",
                "a Flemish Mac gets Dutch")
        #expect(Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: ["de-DE"]).first == "en",
                "a language Cellar doesn't ship falls back to English, not to Dutch")
        // (`preferredLocalizations` can list a language twice — it reads both the folders and the
        // Info.plist — so these ask which one wins, not for the whole list.)
        let declared = bundle.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String]
        #expect(declared == ["en", "nl"])
    }

    @Test("Dutch strings load from the built bundle, including an interpolated one", arguments: scripts)
    func dutchLoadsFromTheBundle(path: String) throws {
        let app = try Self.assembleApp(with: path)
        let dutch = try #require(Bundle(url: app.appendingPathComponent("Contents/Resources/nl.lproj")))
        #expect(dutch.localizedString(forKey: "Sign in", value: nil, table: nil) == "Log in")
        #expect(dutch.localizedString(forKey: "Choose a game", value: nil, table: nil) == "Kies een game")
        let connected = dutch.localizedString(forKey: "Connected: %@", value: nil, table: nil)
        #expect(String(format: connected, "Xbox Wireless Controller") == "Verbonden: Xbox Wireless Controller")
        // Engine copy (CellarDomain, CellarData) resolves against the same bundle: Bundle.main is
        // Cellar.app in the app and in the CLI that bundle-app.sh puts inside it.
        #expect(dutch.localizedString(forKey: "Preparing the bottle", value: nil, table: nil) == "De bottle klaarmaken")
        let days = dutch.localizedString(forKey: "%lld days ago", value: nil, table: nil)
        #expect(String(format: days, 3) == "3 dagen geleden")
        // A key with no entry shows its English text: the fallback a reworded literal would hit.
        #expect(dutch.localizedString(forKey: "Not in the table", value: nil, table: nil) == "Not in the table")
    }
}
