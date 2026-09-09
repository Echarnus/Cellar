import Foundation
import Testing
@testable import CellarKit

/// The store layer. `store = "…"` is the single field that decides the whole pipeline, and
/// `StoreDescriptor` is the one place a per-store difference is allowed to be written down — so
/// these tests guard both the parsing and the table's internal consistency.
@Suite(.serialized)
struct StoreTests {

    @Test("Every spelling a profile might reasonably use resolves",
          arguments: [("steam", GameStore.steam),
                      ("Steam", .steam),
                      ("  STEAM  ", .steam),
                      ("battlenet", .battlenet),
                      ("battle.net", .battlenet),
                      ("blizzard", .battlenet),
                      ("bnet", .battlenet),
                      ("gog", .gog),
                      ("gog.com", .gog),
                      ("gog-galaxy", .gog),
                      ("standalone", .standalone),
                      ("none", .standalone),
                      ("direct", .standalone),
                      ("drm-free", .standalone)])
    func parsesKnownSpellings(_ input: String, _ expected: GameStore) {
        #expect(GameStore(profileValue: input) == expected)
    }

    @Test("An unknown or empty store is nil so the caller can fall back deliberately",
          arguments: [nil, "", "   ", "epic", "itch", "steam2"])
    func rejectsUnknownStores(_ input: String?) {
        #expect(GameStore(profileValue: input) == nil,
                "mis-classifying a store silently would set up the wrong client in the bottle")
    }

    @Test("A profile with no store falls back to Steam, the documented default")
    func defaultsToSteam() throws {
        let plan = try TestHome.plan("""
        [game]
        name = "No Store Named"
        """)
        #expect(plan.store == .steam)
        #expect(GameStore.default == .steam)
    }

    @Test("An unrecognised store falls back rather than throwing")
    func unknownStoreFallsBack() throws {
        let plan = try TestHome.plan("""
        [game]
        store = "epic"
        """)
        #expect(plan.store == .steam)
    }

    // MARK: - Descriptor invariants

    @Test("Every store has a complete, non-empty descriptor", arguments: GameStore.allCases)
    func descriptorIsComplete(_ store: GameStore) {
        let d = store.descriptor
        #expect(d.store == store, "a descriptor must describe the store it is keyed on")
        #expect(!d.displayName.isEmpty)
        #expect(!d.sectionTitle.isEmpty)
        #expect(!d.symbolName.isEmpty)
        #expect(!d.accountNoun.isEmpty)
        #expect(!d.installLocation.isEmpty)
        #expect(d.accentHex.hasPrefix("#") && d.accentHex.count == 7,
                "accent must be #RRGGBB — the app and the CLI both parse it")
    }

    @Test("Store accents are distinct, so two stores never read as the same thing")
    func accentsAreDistinct() {
        let accents = GameStore.allCases.map(\.descriptor.accentHex)
        #expect(Set(accents).count == accents.count)
    }

    @Test("Sort order is a total order with no ties")
    func sortIndexIsTotal() {
        let indices = GameStore.allCases.map(\.sortIndex)
        #expect(Set(indices).count == indices.count)
        #expect(GameStore.steam.sortIndex < GameStore.battlenet.sortIndex)
        #expect(GameStore.standalone.sortIndex == indices.max())
    }

    @Test("Hex accents decode to the components the app draws with")
    func hexDecodes() {
        let black = StoreDescriptor.components(fromHex: "#000000")
        #expect(black.red == 0 && black.green == 0 && black.blue == 0)

        let white = StoreDescriptor.components(fromHex: "#FFFFFF")
        #expect(white.red == 1 && white.green == 1 && white.blue == 1)

        let steam = StoreDescriptor.components(fromHex: "#2C7FBF")
        #expect(abs(steam.red - 44.0 / 255.0) < 0.0001)
        #expect(abs(steam.green - 127.0 / 255.0) < 0.0001)
        #expect(abs(steam.blue - 191.0 / 255.0) < 0.0001)

        // With or without the leading '#'.
        let bare = StoreDescriptor.components(fromHex: "2C7FBF")
        #expect(bare == steam)
    }

    // MARK: - The differences that actually bite

    @Test("Only Battle.net lacks a silent installer, and it is the one that must warn the player")
    func silentInstallerFlags() {
        #expect(GameStore.steam.descriptor.hasSilentInstaller)
        #expect(GameStore.battlenet.descriptor.hasSilentInstaller == false,
                "Blizzard ships no /S switch — setup has to say a window will open")
        #expect(GameStore.gog.descriptor.hasSilentInstaller)
    }

    @Test("Sign-in is only claimed for stores Cellar can actually read")
    func signInDetection() {
        // Steam writes loginusers.vdf; Cellar holds GOG's token itself. Battle.net publishes
        // nothing, so claiming to know would put an untrustworthy ✗ in front of the player.
        #expect(GameStore.steam.descriptor.canDetectSignIn)
        #expect(GameStore.gog.descriptor.canDetectSignIn)
        #expect(GameStore.battlenet.descriptor.canDetectSignIn == false)
        #expect(GameStore.standalone.descriptor.canDetectSignIn == false)
    }

    @Test("A token store signs in once; a client store signs in per window")
    func signsInOnceFollowsAuthStyle() {
        #expect(GameStore.gog.descriptor.signsInOnce)
        #expect(GameStore.steam.descriptor.signsInOnce == false)
        #expect(GameStore.battlenet.descriptor.signsInOnce == false)
        for store in GameStore.allCases {
            #expect(store.descriptor.signsInOnce == (store.descriptor.authStyle == .cellarHeldToken))
        }
    }

    @Test("A store with nothing to sign in to has no account style")
    func standaloneHasNoAuth() {
        #expect(GameStore.standalone.descriptor.authStyle == .none)
        #expect(GameStore.standalone.descriptor.installsClientInBottle == false)
        #expect(GameStore.gog.descriptor.installsClientInBottle == false,
                "GOG is pure HTTP — that is why it needs no per-bottle sign-in")
    }

    @Test("A store that needs no client in the bottle is never asked to set one up",
          arguments: [GameStore.gog, .standalone])
    func clientlessStoresAreAlwaysReady(_ store: GameStore) throws {
        let plan = try TestHome.plan("""
        [game]
        store = "\(store.rawValue)"
        """)
        #expect(Game.storeClientInstalled(plan))
        #expect(Game.storeClientRunning(plan) == false)
    }

    // MARK: - Install-method defaults

    @Test("Each store gets its own default install method")
    func installMethodDefaults() {
        #expect(Game.defaultInstallMethod(for: .steam) == "windows-steam-in-bottle")
        #expect(Game.defaultInstallMethod(for: .battlenet) == "battlenet-in-bottle")
        #expect(Game.defaultInstallMethod(for: .gog) == "gog-installer")
        #expect(Game.defaultInstallMethod(for: .standalone) == "depot")
        #expect(Set(GameStore.allCases.map(Game.defaultInstallMethod(for:))).count == GameStore.allCases.count)
    }

    @Test("A profile's explicit method overrides the store default")
    func explicitMethodWins() throws {
        let plan = try TestHome.plan("""
        [game]
        store = "steam"
        [install]
        method = "depot"
        """)
        #expect(plan.installMethod == "depot")
    }

    // MARK: - The MZ guard

    @Test("A downloaded installer is only run when it really is a Windows executable")
    func portableExecutableGuard() throws {
        let dir = TestHome.scratch("mz")
        let real = dir.appendingPathComponent("Setup.exe")
        let html = dir.appendingPathComponent("Outage.exe")
        let empty = dir.appendingPathComponent("Empty.exe")

        try Data([0x4D, 0x5A, 0x90, 0x00]).write(to: real)
        try Data("<!DOCTYPE html><html><body>503</body></html>".utf8).write(to: html)
        try Data().write(to: empty)

        #expect(WindowsInstaller.isPortableExecutable(real))
        #expect(WindowsInstaller.isPortableExecutable(html) == false,
                "a CDN error page fed to Wine fails in a baffling way — catch it here")
        #expect(WindowsInstaller.isPortableExecutable(empty) == false)
        #expect(WindowsInstaller.isPortableExecutable(dir.appendingPathComponent("missing.exe")) == false)
    }
}
