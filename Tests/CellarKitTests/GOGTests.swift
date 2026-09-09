import Foundation
import Testing
@testable import CellarKit

/// GOG is the one store Cellar talks to directly, so its parsing is Cellar's own responsibility
/// rather than a client's. None of these tests touch the network: they feed the shapes GOG's API
/// actually returns into the functions that read them.
@Suite(.serialized)
struct GOGTests {

    // MARK: - The OAuth hand-off

    @Test("The authorization URL carries everything GOG's login needs")
    func authorizationURL() throws {
        let components = try #require(URLComponents(url: GOG.authorizationURL, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        #expect(components.host == "auth.gog.com")
        #expect(items["client_id"] == GOG.clientID)
        #expect(items["redirect_uri"] == GOG.redirectURI)
        #expect(items["response_type"] == "code")
    }

    @Test("A pasted redirect URL yields the code inside it")
    func extractsCodeFromRedirect() {
        let url = "https://embed.gog.com/on_login_success?origin=client&code=abcdef0123456789abcdef0123456789"
        #expect(GOG.authorizationCode(from: url) == "abcdef0123456789abcdef0123456789")
    }

    @Test("A bare code pasted on its own is accepted")
    func acceptsBareCode() {
        let code = "abcdef0123456789abcdef0123456789"
        #expect(GOG.authorizationCode(from: code) == code)
        #expect(GOG.authorizationCode(from: "  \(code)\n ") == code,
                "people paste with whitespace attached")
    }

    @Test("Anything that is not a code is rejected rather than sent to GOG", arguments: [
        "",
        "   ",
        "short",
        "https://embed.gog.com/on_login_success?origin=client",   // redirect without a code
        "please sign me in",
    ])
    func rejectsNonCodes(_ input: String) {
        #expect(GOG.authorizationCode(from: input) == nil)
    }

    // MARK: - Installer selection

    /// The shape `api.gog.com/products/<id>?expand=downloads` returns.
    private func product(installers: [[String: Any]]) -> [String: Any] {
        ["title": "The Witcher 3", "slug": "the_witcher_3",
         "downloads": ["installers": installers]]
    }

    private func installer(os: String, language: String, files: [[String: Any]]) -> [String: Any] {
        ["os": os, "language": language, "files": files]
    }

    @Test("Only Windows installers are considered — Cellar runs Windows games")
    func picksWindowsOnly() {
        let data = product(installers: [
            installer(os: "linux", language: "en", files: [["id": "lin", "size": 100,
                                                            "downlink": "https://api.gog.com/lin"]]),
            installer(os: "mac", language: "en", files: [["id": "mac", "size": 100,
                                                          "downlink": "https://api.gog.com/mac"]]),
            installer(os: "windows", language: "en", files: [["id": "win", "size": 100,
                                                              "downlink": "https://api.gog.com/win"]]),
        ])
        let files = GOGLibrary.installerFiles(in: data)
        #expect(files.count == 1)
        #expect(files.first?.downlinkURL == "https://api.gog.com/win")
    }

    @Test("A product with no Windows installer yields nothing rather than a Mac one")
    func noWindowsInstaller() {
        let data = product(installers: [
            installer(os: "mac", language: "en", files: [["id": "mac", "size": 1,
                                                          "downlink": "https://api.gog.com/mac"]]),
        ])
        #expect(GOGLibrary.installerFiles(in: data).isEmpty)
    }

    @Test("A product with no downloads section is handled, not crashed on")
    func missingDownloads() {
        #expect(GOGLibrary.installerFiles(in: [:]).isEmpty)
        #expect(GOGLibrary.installerFiles(in: ["downloads": [:]]).isEmpty)
        #expect(GOGLibrary.installerFiles(in: ["downloads": ["installers": []]]).isEmpty)
    }

    @Test("Every part of a multi-file installer is kept, in order")
    func keepsAllParts() {
        // GOG splits big games into setup_*.exe plus -1.bin, -2.bin …; dropping a part gives a
        // setup that fails halfway through with no explanation.
        let data = product(installers: [
            installer(os: "windows", language: "en", files: [
                ["id": "setup", "size": 1_000, "downlink": "https://api.gog.com/0"],
                ["id": "part1", "size": 4_000_000_000, "downlink": "https://api.gog.com/1"],
                ["id": "part2", "size": 2_000, "downlink": "https://api.gog.com/2"],
            ]),
        ])
        let files = GOGLibrary.installerFiles(in: data)
        #expect(files.count == 3)
        #expect(files.map(\.downlinkURL) == ["https://api.gog.com/0",
                                             "https://api.gog.com/1",
                                             "https://api.gog.com/2"])
        #expect(files[1].sizeBytes == 4_000_000_000, "sizes past 2 GB must not overflow")
        #expect(files.allSatisfy { !$0.name.isEmpty }, "a nameless part cannot be resumed")
    }

    @Test("A file with no usable download link is skipped")
    func skipsLinklessFiles() {
        let data = product(installers: [
            installer(os: "windows", language: "en", files: [
                ["id": "good", "size": 10, "downlink": "https://api.gog.com/good"],
                ["id": "bad", "size": 10],
            ]),
        ])
        #expect(GOGLibrary.installerFiles(in: data).count == 1)
    }

    @Test("English is the fallback when the player's own language is not offered")
    func languageFallback() {
        let current = Locale.current.language.languageCode?.identifier ?? "en"
        let offered = ["de", "en"]
        let data = product(installers: offered.map { language in
            installer(os: "windows", language: language,
                      files: [["id": language, "size": 1, "downlink": "https://api.gog.com/\(language)"]])
        })
        let expected = offered.contains(current) ? current : "en"
        #expect(GOGLibrary.installerFiles(in: data).first?.downlinkURL == "https://api.gog.com/\(expected)")
    }

    @Test("A game offered in no familiar language still downloads rather than failing")
    func lastResortLanguage() {
        let data = product(installers: [
            installer(os: "windows", language: "ja",
                      files: [["id": "ja", "size": 1, "downlink": "https://api.gog.com/ja"]]),
        ])
        #expect(GOGLibrary.installerFiles(in: data).count == 1,
                "refusing to download because the language list is unfamiliar would be worse")
    }

    // MARK: - URL normalisation

    @Test("Protocol-relative artwork URLs are made absolute")
    func normalisesProtocolRelativeURLs() {
        #expect(GOGLibrary.normalized("//images.gog.com/abc.jpg") == "https://images.gog.com/abc.jpg")
        #expect(GOGLibrary.normalized("https://images.gog.com/abc.jpg") == "https://images.gog.com/abc.jpg")
        #expect(GOGLibrary.normalized(nil) == nil)
        #expect(GOGLibrary.normalized("") == nil)
    }

    // MARK: - Sizes

    @Test("Download sizes are shown in units a person reads")
    func humanSizes() {
        #expect(GOGInstall.humanSize(0).isEmpty == false)
        #expect(GOGInstall.humanSize(50_000_000_000).contains("GB"))
        #expect(GOGInstall.humanSize(-1).isEmpty == false, "an unknown size must not print garbage")
    }

    @Test("A partially downloaded file is not mistaken for a complete one")
    func resumeDetection() throws {
        let dir = TestHome.scratch("gog-resume")
        let file = dir.appendingPathComponent("setup.exe")
        try Data(repeating: 0, count: 100).write(to: file)

        #expect(GOGInstall.isComplete(file, expecting: 100))
        #expect(GOGInstall.isComplete(file, expecting: 200) == false)
        #expect(GOGInstall.isComplete(dir.appendingPathComponent("missing.exe"), expecting: 100) == false)
    }

    // MARK: - Store wiring

    @Test("A GOG game without a product id cannot be installed, and the error says why")
    func gogNeedsAProductID() throws {
        try #require(TestHome.installStubRunner() != nil)
        let plan = try TestHome.plan("""
        [game]
        name  = "Nameless GOG Game"
        store = "gog"
        """, slug: "gog-noid")

        do {
            try Game.installGame(plan)
            Issue.record("installing a GOG game with no gog_product_id must fail")
        } catch let error as CellarError {
            #expect(error.description.contains("gog_product_id"),
                    "the message must name the missing field: \(error.description)")
        }
    }

    @Test("A GOG game is never sent down the Steam depot path")
    func gogRejectsDepotDownload() throws {
        let plan = try TestHome.plan("""
        [game]
        name  = "A GOG Game"
        store = "gog"
        [install]
        steam_appid = "1"
        """, slug: "gog-depot")

        do {
            try Game.fetchDepot(plan, credentials: .qr) { _ in }
            Issue.record("fetch-depot must refuse a GOG title")
        } catch let error as CellarError {
            #expect(error.description.contains("cellar gog install"),
                    "the error must point at the command that does work")
        }
    }

    @Test("GOG has no client in the bottle to open, and says so")
    func gogHasNoClientToOpen() throws {
        try #require(TestHome.installStubRunner() != nil)
        let plan = try TestHome.plan("[game]\nstore = \"gog\"", slug: "gog-open")
        do {
            try Game.openStoreClient(plan)
            Issue.record("there is no GOG client in a bottle")
        } catch let error as CellarError {
            #expect(error.description.contains("cellar gog login"))
        }
    }
}
