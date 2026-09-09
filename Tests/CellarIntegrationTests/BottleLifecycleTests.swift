import Foundation
import Testing
@testable import CellarKit

/// Tier A: real files, no Wine, no network. Everything Cellar writes to disk before a game is ever
/// involved — bottles, launcher apps, Steam shortcuts — round-tripped through the code that
/// creates and reads them back.
@Suite(.serialized)
struct BottleLifecycleTests {

    @Test("A bottle is created, listed with its backend and runner, and removed")
    func bottleRoundTrip() throws {
        IT.ensure()
        let name = "it-bottle-\(UUID().uuidString.prefix(8))"

        let created = try PrefixManager.create(name: name, backend: .dxvk, runner: "sikarugir")
        #expect(created.name == name)
        #expect(created.backend == "dxvk")
        #expect(FileManager.default.fileExists(atPath: created.url.appendingPathComponent("bottle.toml").path))

        let listed = try PrefixManager.list().first { $0.name == name }
        #expect(listed != nil, "a created bottle must show up in `cellar prefix list`")
        #expect(listed?.backend == "dxvk", "the backend is read back out of bottle.toml, not guessed")
        #expect(listed?.runner == "sikarugir")

        try PrefixManager.remove(name: name)
        let remaining = try PrefixManager.list().map(\.name)
        #expect(remaining.contains(name) == false)
    }

    @Test("Creating a bottle twice is refused rather than silently clobbering a prefix")
    func duplicateBottleRefused() throws {
        IT.ensure()
        let name = "it-dup-\(UUID().uuidString.prefix(8))"
        _ = try PrefixManager.create(name: name, backend: .d3dmetal, runner: "wineforge")
        defer { try? PrefixManager.remove(name: name) }

        #expect(throws: CellarError.self) {
            _ = try PrefixManager.create(name: name, backend: .d3dmetal, runner: "wineforge")
        }
    }

    @Test("Removing a bottle that was never there is an error, not a no-op")
    func removeMissingBottle() throws {
        IT.ensure()
        #expect(throws: CellarError.self) { try PrefixManager.remove(name: "no-such-bottle") }
    }

    @Test("A bottle.toml written by Cellar is readable by Cellar", arguments: GraphicsBackend.allCases)
    func bottleConfigRoundTrip(_ backend: GraphicsBackend) throws {
        IT.ensure()
        let name = "it-cfg-\(backend.rawValue)-\(UUID().uuidString.prefix(6))"
        let info = try PrefixManager.create(name: name, backend: backend, runner: "wineforge")
        defer { try? PrefixManager.remove(name: name) }

        let config = PrefixManager.readBottleConfig(info.url.appendingPathComponent("bottle.toml"))
        #expect(config["name"] == name)
        #expect(config["backend"] == backend.rawValue)
        #expect(config["runner"] == "wineforge")
        #expect(config["windows_version"] == "win10")
    }

    // MARK: - Generated launcher apps

    @Test("A game launcher app is a real, runnable bundle")
    func gameLauncherBundle() throws {
        IT.ensure()
        let name = "IT Fixture Game \(UUID().uuidString.prefix(6))"
        let generated = try AppBundle.generate(name: name, slug: "it-fixture",
                                               cellarBinary: "/usr/local/bin/cellar")
        defer { try? FileManager.default.removeItem(at: generated.app) }

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: generated.app.path))
        #expect(fm.isExecutableFile(atPath: generated.launcher.path),
                "Finder will not launch a bundle whose executable bit is missing")

        let script = try String(contentsOf: generated.launcher, encoding: .utf8)
        #expect(script.hasPrefix("#!/bin/sh"))
        #expect(script.contains("'launch' 'it-fixture'"))
        #expect(script.contains("/usr/local/bin/cellar"),
                "a double-clicked app inherits no PATH, so the cellar path must be absolute")

        let plist = try String(contentsOf: generated.app
            .appendingPathComponent("Contents/Info.plist"), encoding: .utf8)
        #expect(plist.contains("<key>CFBundleExecutable</key><string>launcher</string>"))
        #expect(plist.contains("it.clercq.cellar.it-fixture"))
        #expect(plist.contains(name))

        // It must actually parse as a property list, not merely contain the right substrings.
        let data = try Data(contentsOf: generated.app.appendingPathComponent("Contents/Info.plist"))
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        #expect(parsed?["CFBundleIdentifier"] as? String == "it.clercq.cellar.it-fixture")
        #expect(parsed?["CFBundlePackageType"] as? String == "APPL")
    }

    @Test("A store-client app points at that store's open command", arguments: [GameStore.steam, .battlenet])
    func storeClientBundle(_ store: GameStore) throws {
        IT.ensure()
        let bottle = "it-\(store.rawValue)-\(UUID().uuidString.prefix(6))"
        let generated = try AppBundle.generateStoreClient(store: store, bottle: bottle, slug: "it-fixture",
                                                          cellarBinary: "/usr/local/bin/cellar")
        defer { try? FileManager.default.removeItem(at: generated.app) }

        #expect(generated.app.lastPathComponent == "\(store.displayName) (\(bottle)).app")
        let script = try String(contentsOf: generated.launcher, encoding: .utf8)
        #expect(script.contains("'\(store.rawValue)' 'open' 'it-fixture'"))
    }

    @Test("A standalone game has no store client to wrap, and says so instead of making one")
    func standaloneHasNoClientApp() throws {
        IT.ensure()
        #expect(throws: CellarError.self) {
            _ = try AppBundle.generateStoreClient(store: .standalone, bottle: "b", slug: "s",
                                                  cellarBinary: "/usr/local/bin/cellar")
        }
    }

    @Test("Regenerating a launcher overwrites in place rather than accumulating bundles")
    func regenerateIsIdempotent() throws {
        IT.ensure()
        let name = "IT Idempotent \(UUID().uuidString.prefix(6))"
        let first = try AppBundle.generate(name: name, slug: "it-idem", cellarBinary: "/usr/local/bin/cellar")
        let second = try AppBundle.generate(name: name, slug: "it-idem", cellarBinary: "/opt/cellar")
        defer { try? FileManager.default.removeItem(at: first.app) }

        #expect(first.app == second.app)
        let script = try String(contentsOf: second.launcher, encoding: .utf8)
        #expect(script.contains("/opt/cellar"), "the second generation must win")
    }

    // MARK: - Steam shortcuts

    @Test("Shortcuts accumulate in shortcuts.vdf and every one parses back")
    func shortcutsAccumulate() throws {
        let dir = IT.scratch("shortcuts")
        let launcher = URL(fileURLWithPath: "/Users/x/Applications/Fixture.app/Contents/MacOS/launcher")

        var ids: [UInt32] = []
        for index in 1...5 {
            ids.append(try SteamShortcuts.add(
                SteamShortcutEntry(appName: "Fixture \(index)", launcherBinary: launcher), to: dir))
        }
        #expect(Set(ids).count == 5, "each shortcut needs its own appid")
        #expect(ids.allSatisfy { $0 & 0x8000_0000 != 0 }, "non-Steam shortcuts set the high bit")

        let data = try Data(contentsOf: dir.appendingPathComponent("shortcuts.vdf"))
        guard case .map(let root) = try BinaryVDF.parse(data),
              case .map(let entries)? = root.first(where: { $0.0 == "shortcuts" })?.1 else {
            Issue.record("shortcuts.vdf did not parse back into a shortcuts map")
            return
        }
        #expect(entries.count == 5)
        #expect(entries.map { $0.0 } == ["0", "1", "2", "3", "4"], "Steam keys entries by ordinal")
    }

    @Test("The same game always gets the same appid, so re-adding does not duplicate artwork")
    func shortcutAppIDIsStable() {
        let exe = "\"/Users/x/Applications/Fixture.app/Contents/MacOS/launcher\""
        let first = SteamShortcuts.appID(exe: exe, appName: "Fixture")
        let again = SteamShortcuts.appID(exe: exe, appName: "Fixture")
        let other = SteamShortcuts.appID(exe: exe, appName: "Different")
        #expect(first == again)
        #expect(first != other)
    }

    // MARK: - The library the GUI actually renders

    @Test("Every shipped profile becomes a summary the app can draw")
    func summariesCoverTheDatabase() throws {
        _ = IT.shippedProfilesStaged
        // Read what ships, not a fixture — this is the database the app renders.
        let shipped = try FileManager.default
            .contentsOfDirectory(at: IT.shippedProfilesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "toml" }
        #expect(!shipped.isEmpty, "the profile database must not be empty")

        let summaries = Game.summaries()
        for url in shipped {
            let slug = url.deletingPathExtension().lastPathComponent
            guard let summary = summaries.first(where: { $0.slug == slug }) else {
                Issue.record("profile '\(slug)' produced no GameSummary — the app would not list it")
                continue
            }
            #expect(!summary.name.isEmpty)
            #expect(!summary.actionTitle.isEmpty)
            #expect(!summary.actionHint.isEmpty)
        }
    }
}
