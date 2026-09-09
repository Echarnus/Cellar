import Foundation
import Testing
@testable import CellarKit

/// Battle.net's side of the store layer. Nothing here can be checked against a running client, so
/// these tests pin the two things Cellar gets wrong most easily: the config merge (which must not
/// erase the player's own settings) and the account read (which must return *unknown*, not "nobody").
@Suite(.serialized)
struct BattleNetTests {

    /// A bottle with one Windows user directory, optionally holding a Battle.net.config.
    private func bottle(config: String? = nil, user: String = "cellar") throws -> URL {
        let prefix = TestHome.scratch("bnet")
        let dir = prefix.appendingPathComponent("drive_c/users/\(user)/AppData/Roaming/Battle.net",
                                                isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let config {
            try config.write(to: dir.appendingPathComponent("Battle.net.config"),
                             atomically: true, encoding: .utf8)
        }
        return prefix
    }

    // MARK: - Layout and readiness

    @Test("The client lives where Blizzard's installer puts it")
    func layout() {
        let prefix = URL(fileURLWithPath: "/bottles/d4")
        #expect(BattleNetBottle.directory(in: prefix).path
            == "/bottles/d4/drive_c/Program Files (x86)/Battle.net")
        #expect(BattleNetBottle.launcherExecutable(in: prefix).path.contains("Battle.net"))
    }

    @Test("An empty bottle has no client and no account")
    func emptyBottle() throws {
        let prefix = try bottle()
        #expect(BattleNetBottle.isInstalled(in: prefix) == false)
        #expect(BattleNetBottle.isClientUpdated(in: prefix) == false)
        #expect(BattleNetBottle.rememberedAccount(in: prefix) == nil)
    }

    @Test("The bootstrapper is not the client — until Battle.net.exe exists nothing can be launched")
    func launcherIsNotTheClient() throws {
        let prefix = try bottle()
        let launcher = BattleNetBottle.launcherExecutable(in: prefix)
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: launcher)

        #expect(BattleNetBottle.isInstalled(in: prefix))
        #expect(BattleNetBottle.isClientUpdated(in: prefix) == false)

        try Data("MZ".utf8).write(to: BattleNetBottle.clientExecutable(in: prefix))
        #expect(BattleNetBottle.isClientUpdated(in: prefix))
    }

    @Test("The Public profile is never mistaken for a player's")
    func skipsPublicUser() throws {
        let prefix = TestHome.scratch("bnet-public")
        let dir = prefix.appendingPathComponent("drive_c/users/Public/AppData/Roaming/Battle.net",
                                                isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"Client":{"Saved":{"Email":"nobody@example.com"}}}"#
            .write(to: dir.appendingPathComponent("Battle.net.config"), atomically: true, encoding: .utf8)

        #expect(BattleNetBottle.rememberedAccount(in: prefix) == nil)
        #expect(BattleNetBottle.userDirectories(in: prefix).isEmpty)
    }

    // MARK: - The remembered account

    @Test("A remembered login is reported when the config carries one")
    func readsRememberedAccount() throws {
        let prefix = try bottle(config: """
        {"Client": {"Saved": {"AccountsExport": "player@example.com,other@example.com"}}}
        """)
        #expect(BattleNetBottle.rememberedAccount(in: prefix) == "player@example.com",
                "the first of a comma-separated list is the most recent login")
    }

    @Test("Fallback keys are tried in order", arguments: ["AccountsExport", "LastLoginAddress", "Email"])
    func fallbackKeys(_ key: String) throws {
        let prefix = try bottle(config: #"{"Client": {"Saved": {"\#(key)": "player@example.com"}}}"#)
        #expect(BattleNetBottle.rememberedAccount(in: prefix) == "player@example.com")
    }

    @Test("Anything unreadable is 'unknown', never 'nobody'", arguments: [
        "not json at all",
        "{}",
        #"{"Client": {}}"#,
        #"{"Client": {"Saved": {}}}"#,
        #"{"Client": {"Saved": {"Email": ""}}}"#,
        #"{"Client": {"Saved": {"Email": "   "}}}"#,
    ])
    func unreadableConfigIsUnknown(_ config: String) throws {
        // The whole Battle.net readiness ladder rests on this: nil means Cellar cannot tell, and
        // GameSummary must never turn that into a ✗ beside "account".
        let prefix = try bottle(config: config)
        #expect(BattleNetBottle.rememberedAccount(in: prefix) == nil)
    }

    // MARK: - The config merge

    @Test("Cellar's settings are applied without discarding the player's")
    func mergePreservesExistingSettings() {
        let existing: [String: Any] = [
            "Client": ["GameLaunchWindowBehavior": "1", "PlayerOwnSetting": "keep me"],
            "SomethingCellarNeverTouches": ["a": "b"],
        ]
        let merged = BattleNetBottle.merge(["Client": ["GameLaunchWindowBehavior": "2"]], into: existing)

        let client = merged["Client"] as? [String: Any]
        #expect(client?["GameLaunchWindowBehavior"] as? String == "2", "Cellar's value wins on a leaf")
        #expect(client?["PlayerOwnSetting"] as? String == "keep me",
                "a sibling key the player set must survive — this is somebody's real config file")
        #expect(merged["SomethingCellarNeverTouches"] != nil)
    }

    @Test("Merging into nothing yields exactly the new settings")
    func mergeIntoEmpty() {
        let merged = BattleNetBottle.merge(["Sound": ["Enabled": "false"]], into: [:])
        #expect((merged["Sound"] as? [String: Any])?["Enabled"] as? String == "false")
    }

    @Test("A scalar replaces a nested value rather than silently merging into it")
    func mergeTypeChange() {
        let merged = BattleNetBottle.merge(["HardwareAcceleration": "false"],
                                           into: ["HardwareAcceleration": ["nested": "value"]])
        #expect(merged["HardwareAcceleration"] as? String == "false")
    }

    @Test("writeClientConfig produces JSON Battle.net can read back")
    func writesReadableConfig() throws {
        let prefix = try bottle(config: #"{"Client": {"PlayerOwnSetting": "keep me"}}"#)
        try BattleNetBottle.writeClientConfig(in: prefix)

        let file = BattleNetBottle.configFiles(in: prefix, existingOnly: true).first
        let data = try Data(contentsOf: try #require(file))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let client = try #require(root["Client"] as? [String: Any])

        // Battle.net stores these as JSON *strings*; writing real booleans is silently ignored.
        #expect(client["GameLaunchWindowBehavior"] as? String == "2")
        #expect(client["PlayerOwnSetting"] as? String == "keep me")
        #expect(root["HardwareAcceleration"] as? String == "false")
        #expect((root["Sound"] as? [String: Any])?["Enabled"] as? String == "false")
    }

    @Test("A bottle with no Windows user directory is an error, not a silent no-op")
    func noUserDirectory() throws {
        let prefix = TestHome.scratch("bnet-empty")
        #expect(throws: CellarError.self) { try BattleNetBottle.writeClientConfig(in: prefix) }
    }
}
