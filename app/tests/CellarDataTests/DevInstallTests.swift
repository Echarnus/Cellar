import Foundation
import Testing
@testable import CellarData

/// A build from source must never pass for the release (#338).
///
/// The release updates itself; a build from `install-app.sh` deliberately does not. When both were
/// called "Cellar", Spotlight and Launchpad offered two of them, and the one the maintainer kept
/// opening was the dev build — which then never showed the update that was waiting.
@Suite(.serialized)
struct DevInstallTests {

    private static func installScript() throws -> String {
        try String(contentsOf: Repo.app.appendingPathComponent("Scripts/install-app.sh"), encoding: .utf8)
    }

    @Test("A local build installs as Cellar Dev, never as Cellar.app")
    func installsUnderItsOwnName() throws {
        let script = try Self.installScript()
        #expect(script.contains(#"APP="$HOME/Applications/Cellar Dev.app""#))
        #expect(!script.contains(#"APP="$HOME/Applications/Cellar.app""#))
        #expect(script.contains("<key>CFBundleName</key><string>Cellar Dev</string>"))
        #expect(script.contains("<key>CFBundleDisplayName</key><string>Cellar Dev</string>"))
        // …and the bundle identifier stays the release's, so both read and write the same data.
        #expect(script.contains("<key>CFBundleIdentifier</key><string>\(Reset.appIdentifier)</string>"))
    }

    @Test("A dev build still never points at the release feed")
    func devBuildHasNoUpdater() throws {
        let script = try Self.installScript()
        #expect(!script.contains("<key>SUFeedURL</key>"))
        #expect(!script.contains("<key>SUPublicEDKey</key>"))
    }

    @Test("The old dev Cellar.app is moved to the Bin, and only when it is a dev build")
    func oldDevCopyIsClearedButNeverTheRelease() throws {
        let script = try Self.installScript()
        let check = try #require(script.range(of: #"OLD="$HOME/Applications/Cellar.app""#),
                                 "install-app.sh no longer clears the dev build it used to install as Cellar.app")
        let rest = script[check.upperBound...]
        // The move sits inside the `*-dev)` arm, so a release (no suffix) never reaches it.
        let devArm = try #require(rest.range(of: "*-dev)"))
        let move = try #require(rest.range(of: #"mv "$OLD" "$HOME/.Trash/"#))
        let close = try #require(rest.range(of: "esac"))
        #expect(devArm.upperBound <= move.lowerBound && move.upperBound <= close.lowerBound)
        #expect(!rest[..<close.lowerBound].contains(#"rm -rf "$OLD""#), "the old copy goes to the Bin, not away for good")
    }

    @Test("Uninstall and reset count Cellar Dev as Cellar")
    func devAppIsFoundByReset() throws {
        TestHome.ensure()
        let dir = TestHome.applicationsDirectory
        let app = dir.appendingPathComponent(Reset.devAppName, isDirectory: true)
        try? FileManager.default.removeItem(at: app)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: app) }
        let plist: [String: Any] = ["CFBundleIdentifier": Reset.appIdentifier, "CFBundleExecutable": "CellarApp"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))

        #expect(Reset.cellarApps.map(\.standardizedFileURL.path).contains(app.standardizedFileURL.path))
        #expect(!AppBundle.isGenerated(app), "Cellar Dev is the app, not a launcher it made")
    }
}
