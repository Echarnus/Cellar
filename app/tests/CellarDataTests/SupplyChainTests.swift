import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// What Cellar downloads and then runs, and what a downloaded game database may make it do.
/// Each test here stands for a way a file someone else controls could become code on the Mac.
@Suite(.serialized)
struct SupplyChainTests {

    // MARK: - Pinned downloads

    @Test("Every runner artifact and DepotDownloader carries a well-formed SHA-256 pin")
    func everyDownloadIsPinned() {
        for spec in RunnerCatalog.all {
            for artifact in spec.artifacts {
                #expect(Checksum.isWellFormed(artifact.sha256), "\(spec.id): \(artifact.url)")
                #expect(artifact.url.hasPrefix("https://"), "\(spec.id): \(artifact.url)")
            }
        }
        #expect(Checksum.isWellFormed(DepotTool.downloadSHA256))
        #expect(DepotTool.downloadURL.hasPrefix("https://"))
        // The SHA-256 of nothing at all: what a failed, empty download hashes to. Never a valid pin.
        let empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        #expect(!RunnerCatalog.all.flatMap(\.artifacts).contains { $0.sha256 == empty })
        #expect(DepotTool.downloadSHA256 != empty)
    }

    @Test("A file that matches its pin is kept; one changed byte is refused and deleted")
    func verify() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-pin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        // NIST's test vector for "abc".
        let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect(try Checksum.sha256(of: file) == abc)
        try Checksum.verify(file, sha256: abc, what: "fixture")
        #expect(FileManager.default.fileExists(atPath: file.path))

        try Data("abd".utf8).write(to: file)
        #expect(throws: Checksum.Failure.self) { try Checksum.verify(file, sha256: abc, what: "fixture") }
        #expect(!FileManager.default.fileExists(atPath: file.path), "a refused download must not stay in the cache")

        try Data("abc".utf8).write(to: file)
        #expect(throws: Checksum.Failure.self) { try Checksum.verify(file, sha256: "", what: "fixture") }
        #expect(!Checksum.isWellFormed(abc.uppercased()))
    }

    @Test("A mismatch says what happened in the player's words, not a stack trace")
    func mismatchWording() {
        let text = Checksum.Failure.mismatch(what: "WineForge", expected: String(repeating: "a", count: 64),
                                             actual: String(repeating: "b", count: 64)).description
        #expect(text.contains("WineForge"))
        #expect(text.contains("nothing was installed"))
    }

    // MARK: - Secrets off curl's command line

    @Test("A token and a refresh token travel in curl's config on stdin, quoted so they cannot add options")
    func secretConfig() {
        #expect(Downloader.secretConfig(bearer: nil, form: nil) == nil)
        let bearer = Downloader.secretConfig(bearer: "tok", form: nil)
        #expect(bearer == "header = \"Authorization: Bearer tok\"\n")
        let form = Downloader.secretConfig(bearer: nil, form: ["refresh_token": "r+1", "grant_type": "refresh_token"])
        #expect(form == "data = \"grant_type=refresh_token&refresh_token=r%2B1\"\n")

        // A hostile value cannot close its quote or start a new line (and with it a new option).
        let hostile = Downloader.secretConfig(bearer: "a\"\nurl = \"https://evil.example\\", form: nil) ?? ""
        #expect(hostile.split(separator: "\n").count == 1)
        #expect(hostile == "header = \"Authorization: Bearer a\\\"url = \\\"https://evil.example\\\\\"\n")
    }

    @Test("Every curl Cellar starts refuses plain HTTP, redirects included")
    func httpsOnly() {
        #expect(Downloader.httpsOnly == ["--proto", "=https", "--proto-redir", "=https"])
    }

    // MARK: - Launchers

    @Test("A launcher script quotes every word, so a name or slug can never become a command")
    func launcherQuoting() {
        let script = AppBundle.launcherScript(cellarBinary: "/Users/o'neil/.local/bin/cellar",
                                              arguments: ["launch", "x'; rm -rf ~; '", "$(touch /tmp/p)"])
        #expect(script == "#!/bin/sh\nexec '/Users/o'\\''neil/.local/bin/cellar' 'launch' 'x'\\''; rm -rf ~; '\\''' '$(touch /tmp/p)'\n")
    }

    @Test("A launcher script runs the arguments it was given, exactly", .enabled(if: FileManager.default.isExecutableFile(atPath: "/bin/sh")))
    func launcherRuns() throws {
        // `printf` stands in for cellar: what the shell hands it is what cellar would receive.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-launcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("pwned")
        let script = AppBundle.launcherScript(cellarBinary: "/usr/bin/printf",
                                              arguments: ["%s|", "it's", "$(touch \(marker.path))", "`id`"])
        let file = dir.appendingPathComponent("launcher")
        try script.write(to: file, atomically: true, encoding: .utf8)
        let result = Shell.run("/bin/sh", [file.path])
        #expect(result.stdout == "it's|$(touch \(marker.path))|`id`|")
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("A game's name is a file name and a plist string, never a path or markup")
    func names() {
        #expect(AppBundle.bundleName("Planet Coaster 2") == "Planet Coaster 2")
        #expect(AppBundle.bundleName("../../Library/LaunchAgents/x") == "-..-Library-LaunchAgents-x")
        #expect(AppBundle.bundleName("..") == "Game")
        #expect(AppBundle.bundleName("A:B\nC") == "A-B-C")
        #expect(AppBundle.xmlEscaped("Tom & Jerry's </string><key>") == "Tom &amp; Jerry&apos;s &lt;/string&gt;&lt;key&gt;")
    }

    // MARK: - The downloaded game database

    @Test("A downloaded profile's file name must be a slug")
    func slugNames() {
        #expect(ProfileUpdates.isSafeName("planet-coaster-2.toml"))
        #expect(ProfileUpdates.isSafeName("diablo-4.toml"))
        for bad in ["x'$(id)'.toml", "Big Game.toml", "-x.toml", ".toml", "a.toml.sh", "../a.toml", "A.toml", "a;b.toml"] {
            #expect(!ProfileUpdates.isSafeName(bad), "\(bad)")
        }
    }

    @Test("Every profile in the repository passes the downloaded-name rule")
    func repositoryProfilesAreSlugs() throws {
        for url in try Repo.profileFiles() {
            #expect(ProfileUpdates.isSafeName(url.lastPathComponent), "\(url.lastPathComponent)")
        }
    }

    @Test("An [env] block cannot set what decides which code runs")
    func envDenyList() throws {
        for denied in ["DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH", "LD_PRELOAD",
                       "WINELOADER", "WINESERVER", "WINEPREFIX", "WINEDLLPATH", "WINEDLLPATH_PREPEND",
                       "PATH", "HOME", "CELLAR_HOME", "D3DMETAL_RUNTIME_DIR", "GST_PLUGIN_PATH", ""] {
            #expect(!ProfileStore.isAllowedEnvKey(denied), "\(denied)")
        }
        for allowed in ["MTL_HUD_ENABLED", "ROSETTA_ADVERTISE_AVX", "WINEDLLOVERRIDES", "WINEDEBUG",
                        "DXVK_HUD", "D3DM_ENABLE_METALFX", "WINEMSYNC"] {
            #expect(ProfileStore.isAllowedEnvKey(allowed), "\(allowed)")
        }

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-env-\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: file) }
        try """
        [game]
        name = "Fixture"
        [env]
        MTL_HUD_ENABLED = "1"
        DYLD_INSERT_LIBRARIES = "/tmp/evil.dylib"
        WINELOADER = "/tmp/evil"
        """.write(to: file, atomically: true, encoding: .utf8)
        #expect(ProfileStore.env(at: file) == ["MTL_HUD_ENABLED": "1"])
    }

    @Test("Every profile in the repository keeps to the allowed [env] keys")
    func repositoryEnvIsAllowed() throws {
        for url in try Repo.profileFiles() {
            let text = try String(contentsOf: url, encoding: .utf8)
            var inEnv = false
            for raw in text.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("[") { inEnv = line == "[env]"; continue }
                guard inEnv, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                #expect(ProfileStore.isAllowedEnvKey(key), "\(url.lastPathComponent): \(key)")
            }
        }
    }

    // MARK: - The updater

    @Test("A release build checks an update's signature before unpacking it")
    func sparkleVerifiesBeforeExtraction() throws {
        let script = try String(contentsOf: Repo.app.appendingPathComponent("Scripts/package.sh"), encoding: .utf8)
        #expect(script.contains("<key>SUVerifyUpdateBeforeExtraction</key><true/>"))
        #expect(script.contains("<key>SUPublicEDKey</key>"))
        #expect(script.contains("<key>SUAllowsAutomaticUpdates</key><false/>"))
    }

    // MARK: - The signing keys

    @Test("A release publishes the signed game database once its key exists, and the bundler finds the profiles")
    func releasePublishesGameDatabase() throws {
        let workflow = try String(contentsOf: Repo.root.appendingPathComponent(".github/workflows/release.yml"), encoding: .utf8)
        #expect(workflow.contains("PROFILES_SIGNING_KEY: ${{ secrets.PROFILES_SIGNING_KEY }}"))
        #expect(workflow.contains("swift Scripts/profiles-bundle.swift \"$VERSION\" dist"))
        #expect(workflow.contains("dist/profiles.json dist/profiles.json.sig"))
        // The bundler runs from app/Scripts; the profiles live at the checkout root.
        let bundler = try String(contentsOf: Repo.app.appendingPathComponent("Scripts/profiles-bundle.swift"), encoding: .utf8)
        #expect(bundler.contains("root.deletingLastPathComponent().appendingPathComponent(\"profiles\""))
        #expect(bundler.contains("--public-key"))
    }

    @Test("The one-time key script keeps private keys off disk and out of the repository")
    func signingKeysScript() throws {
        let script = try String(contentsOf: Repo.app.appendingPathComponent("Scripts/signing-keys.sh"), encoding: .utf8)
        #expect(script.contains("sh Scripts/sparkle-keys.sh"))
        #expect(script.contains("gh secret set PROFILES_SIGNING_KEY --repo \"$REPO\" --env release"))
        #expect(script.contains("security add-generic-password -s \"$SERVICE\""), "the keychain copy is the backup")
        #expect(!script.contains("> \"$"), "a private key is never redirected into a file")
        #expect(script.contains("ProfileUpdates.swift"))
    }
}
