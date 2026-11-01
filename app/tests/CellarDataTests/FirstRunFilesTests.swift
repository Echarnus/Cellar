import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Skyrim Special Edition crashed on every start in Cellar (2026-11-01): eight starts, eight exits,
/// the first with code 54 and the rest with 0xC0000005, while its `My Games` folder stayed empty.
/// Steam's own Play would have started `SkyrimSELauncher.exe`, which writes `Skyrim.ini` and
/// `SkyrimPrefs.ini` on its first run. Cellar starts `SkyrimSE.exe` itself, so nobody wrote them.
///
/// These tests hold Cellar to writing what a profile's `first_run_files` names, the way the
/// launcher would: from the game's own files, only where nothing exists, and before the game starts.
@Suite(.serialized)
struct FirstRunFilesTests {

    // MARK: - The profile's value

    @Test("A profile's pairs are read as source > destination, with Windows separators accepted")
    func parsesPairs() {
        let copies = FirstRunFiles.parse(#"Skyrim_Default.ini > Documents\My Games\Skyrim Special Edition\Skyrim.ini; High.ini >Documents/My Games/Skyrim Special Edition/SkyrimPrefs.ini"#)
        #expect(copies == [
            .init(source: "Skyrim_Default.ini", destination: "Documents/My Games/Skyrim Special Edition/Skyrim.ini"),
            .init(source: "High.ini", destination: "Documents/My Games/Skyrim Special Edition/SkyrimPrefs.ini"),
        ])
    }

    @Test("A pair that is half missing, or climbs out of its folder, is dropped rather than guessed at")
    func dropsWhatItCannotTrust() {
        #expect(FirstRunFiles.parse(nil).isEmpty)
        #expect(FirstRunFiles.parse("").isEmpty)
        #expect(FirstRunFiles.parse("Skyrim.ini").isEmpty, "no destination")
        #expect(FirstRunFiles.parse(" > Documents/X.ini").isEmpty, "no source")
        #expect(FirstRunFiles.parse("A.ini > ../../Library/X.ini").isEmpty, "never outside the user folder")
        #expect(FirstRunFiles.parse("../../etc/passwd > Documents/X").isEmpty, "never outside the game")
        #expect(FirstRunFiles.parse("A.ini > Documents/A.ini; nonsense").count == 1)
    }

    // MARK: - Writing them

    /// A game folder holding the launcher's sources, and a Windows user folder whose Documents is
    /// a link to a separate folder, the way Wine links it to the Mac's `~/Documents`.
    private func folders() throws -> (game: URL, user: URL, macDocuments: URL) {
        let root = TestHome.scratch("first-run")
        let game = root.appendingPathComponent("Skyrim Special Edition", isDirectory: true)
        let user = root.appendingPathComponent("drive_c/users/player", isDirectory: true)
        let macDocuments = root.appendingPathComponent("MacDocuments", isDirectory: true)
        let fm = FileManager.default
        for dir in [game, user, macDocuments] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        try fm.createSymbolicLink(at: user.appendingPathComponent("Documents"), withDestinationURL: macDocuments)
        try "[General]\nsLanguage=ENGLISH\n".write(to: game.appendingPathComponent("Skyrim_Default.ini"),
                                                    atomically: true, encoding: .utf8)
        try "[Display]\niPresentInterval=1\n".write(to: game.appendingPathComponent("High.ini"),
                                                     atomically: true, encoding: .utf8)
        return (game, user, macDocuments)
    }

    static let skyrimCopies = FirstRunFiles.parse(
        "Skyrim_Default.ini > Documents/My Games/Skyrim Special Edition/Skyrim.ini; "
        + "High.ini > Documents/My Games/Skyrim Special Edition/SkyrimPrefs.ini")

    @Test("Missing settings are copied from the game's own files, through the Documents link")
    func writesWhatIsMissing() throws {
        let (game, user, macDocuments) = try folders()
        let written = FirstRunFiles.seed(Self.skyrimCopies, gameFolder: game, userFolder: user)
        #expect(written.count == 2)
        let mine = macDocuments.appendingPathComponent("My Games/Skyrim Special Edition")
        #expect(try String(contentsOf: mine.appendingPathComponent("Skyrim.ini"), encoding: .utf8)
                == "[General]\nsLanguage=ENGLISH\n")
        #expect(try String(contentsOf: mine.appendingPathComponent("SkyrimPrefs.ini"), encoding: .utf8)
                == "[Display]\niPresentInterval=1\n", "the preset becomes the prefs file, as the launcher does")
    }

    @Test("A settings file that already exists is never overwritten: the player's changes are theirs")
    func neverOverwrites() throws {
        let (game, user, macDocuments) = try folders()
        let mine = macDocuments.appendingPathComponent("My Games/Skyrim Special Edition")
        try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
        try "[Display]\niSize W=3024\n".write(to: mine.appendingPathComponent("SkyrimPrefs.ini"),
                                              atomically: true, encoding: .utf8)

        let written = FirstRunFiles.seed(Self.skyrimCopies, gameFolder: game, userFolder: user)

        #expect(written.map(\.lastPathComponent) == ["Skyrim.ini"], "only the missing one is written")
        #expect(try String(contentsOf: mine.appendingPathComponent("SkyrimPrefs.ini"), encoding: .utf8)
                == "[Display]\niSize W=3024\n")
        #expect(FirstRunFiles.seed(Self.skyrimCopies, gameFolder: game, userFolder: user).isEmpty,
                "the second launch has nothing to do")
    }

    @Test("A source the game doesn't have, or a bottle with no user folder yet, writes nothing")
    func nothingToCopyFrom() throws {
        let (game, user, macDocuments) = try folders()
        let missing = FirstRunFiles.parse("Ultra.ini > Documents/My Games/X/SkyrimPrefs.ini")
        #expect(FirstRunFiles.seed(missing, gameFolder: game, userFolder: user).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: macDocuments.appendingPathComponent("My Games/X").path),
                "no empty folder left behind for a copy that couldn't be made")
        let noUser = user.deletingLastPathComponent().appendingPathComponent("nobody")
        #expect(FirstRunFiles.seed(Self.skyrimCopies, gameFolder: game, userFolder: noUser).isEmpty)
    }

    // MARK: - Before Play

    /// A store whose launch only records whether the settings were on disk by the time it was asked.
    final class Seen: @unchecked Sendable { var settingsExisted: Bool? }

    struct CheckingAdapter: StoreAdapter {
        let settings: URL
        let seen: Seen
        var store: GameStore { .steam }
        func isClientInstalled(_ plan: GamePlan) -> Bool { true }
        var isClientRunning: Bool { false }
        func signedInAccount(_ plan: GamePlan) -> String? { nil }
        func recordsGameInstalled(_ plan: GamePlan) -> Bool? { nil }
        func setUpClient(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                         phase: (InstallProgress) -> Void) throws {}
        func installGame(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                         progress: (String) -> Void, phase: (InstallProgress) -> Void) throws {}
        func openClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool) throws {}
        func launchThroughClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool, forceStore: Bool,
                                 progress: (String) -> Void, stage: (LaunchStage) -> Void,
                                 update: (InstallProgress) -> Void) throws -> LaunchRoute {
            seen.settingsExisted = FileManager.default.fileExists(atPath: settings.path)
            return .steamAlongside(exeName: "SkyrimSE.exe", appID: 489830)
        }
    }

    @Test("Play writes the profile's first-run settings before the store is asked to start the game")
    func playWritesThemFirst() throws {
        let install = try FakeWine.install()
        let plan = try TestHome.plan("""
        [game]
        name        = "First Run Fixture"
        store       = "steam"
        steam_appid = 489830
        [runner]
        id = "\(install.spec.id)"
        [launch]
        exe = "SkyrimSE.exe"
        first_run_files = "Skyrim_Default.ini > Documents/My Games/First Run Fixture/Skyrim.ini"
        """, slug: "first-run")
        defer { try? FileManager.default.removeItem(at: plan.prefix) }
        try TestHome.installFakeGame(into: plan, at: "SkyrimSE.exe")
        try "[General]\n".write(to: plan.depotGameDir.appendingPathComponent("Skyrim_Default.ini"),
                                atomically: true, encoding: .utf8)
        let user = FirstRunFiles.userFolder(of: plan)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        let settings = user.appendingPathComponent("Documents/My Games/First Run Fixture/Skyrim.ini")

        #expect(plan.firstRunFiles.count == 1, "the profile's value reaches the plan")
        let seen = Seen()
        var lines: [String] = []
        try LaunchGame(plan, checkUpdates: false, adapter: CheckingAdapter(settings: settings, seen: seen))
            .run { if let text = $0.sentence { lines.append(text) } }

        #expect(seen.settingsExisted == true, "the game would have started without its settings")
        #expect(lines.contains { $0.contains("First Run Fixture") && $0.contains("first start") },
                "the player is told why a step happened before the game appeared")
    }

    // MARK: - The shipped profile

    @Test("Skyrim's shipped profile names both files its launcher writes, from files the game ships")
    func skyrimProfile() throws {
        let source = Repo.profiles.appendingPathComponent("skyrim-special-edition.toml")
        let target = TestHome.profilesDirectory.appendingPathComponent("skyrim-special-edition.toml")
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
        let plan = try Game.plan(slug: "skyrim-special-edition")

        #expect(plan.launchExe == "SkyrimSE.exe", "Cellar starts the game, not SkyrimSELauncher.exe")
        #expect(plan.firstRunFiles == Self.skyrimCopies)
    }
}
