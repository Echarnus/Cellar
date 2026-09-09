import Testing
import Foundation
@testable import CellarKit

/// `GameStore.descriptor` is the single table every layer reads its store vocabulary from — the CLI,
/// the app, and the setup/launch pipelines. A gap or a contradiction in it does not fail loudly; it
/// shows up as a blank word in the UI, or as Cellar claiming to know something it cannot check.
/// These tests hold the table to the promises `Store.swift` makes in prose.
@Suite("Store descriptors")
struct StoreDescriptorTests {

    @Test("every store spells out every word the UI puts on screen", arguments: GameStore.allCases)
    func vocabularyIsComplete(store: GameStore) {
        let d = store.descriptor
        #expect(d.store == store, "descriptor for .\(store.rawValue) reports itself as .\(d.store.rawValue)")
        #expect(!d.displayName.isEmpty)
        #expect(!d.sectionTitle.isEmpty)
        #expect(!d.symbolName.isEmpty)
        #expect(!d.accountNoun.isEmpty)
        #expect(!d.installLocation.isEmpty)
    }

    @Test("accents are real six-digit hex, and no two stores share one", arguments: GameStore.allCases)
    func accentIsWellFormed(store: GameStore) {
        let hex = store.descriptor.accentHex
        #expect(hex.hasPrefix("#"), "\(store.rawValue) accent '\(hex)' should be written #RRGGBB")
        #expect(hex.count == 7, "\(store.rawValue) accent '\(hex)' should be six hex digits")
        let digitsAreHex = hex.dropFirst().allSatisfy(\.isHexDigit)
        #expect(digitsAreHex, "\(store.rawValue) accent '\(hex)' is not hex")

        // A malformed string would scan to black rather than throwing, so check the parse too.
        let rgb = store.descriptor.accentColorComponents
        for c in [rgb.red, rgb.green, rgb.blue] {
            #expect(c >= 0 && c <= 1)
        }
    }

    @Test("no two stores share an accent, a name or a sort position")
    func storesAreDistinguishable() {
        let all = GameStore.allCases
        #expect(Set(all.map(\.descriptor.accentHex)).count == all.count, "two stores share an accent colour")
        #expect(Set(all.map(\.descriptor.displayName)).count == all.count, "two stores share a display name")
        #expect(Set(all.map(\.sortIndex)).count == all.count, "two stores share a sort position")
    }

    /// The honesty rule, as a test. `skills/ux.md` forbids a ✓ for something Cellar cannot check, and
    /// the fact that decides it is `canDetectSignIn`. Battle.net publishes nothing comparable to
    /// Steam's `loginusers.vdf`, so it must stay false — if someone flips it, the app starts showing
    /// a sign-in state it invented.
    @Test("Cellar only claims to detect a sign-in where it really can")
    func signInDetectionIsHonest() {
        #expect(GameStore.steam.descriptor.canDetectSignIn, "Steam writes loginusers.vdf")
        #expect(GameStore.gog.descriptor.canDetectSignIn, "Cellar holds GOG's token itself")
        #expect(GameStore.battlenet.descriptor.canDetectSignIn == false,
                "Blizzard publishes no signed-in state — Cellar must not guess one")
        #expect(GameStore.standalone.descriptor.canDetectSignIn == false, "nothing to sign in to")
    }

    /// Battle.net's installer has no silent switch, which is why setup has to warn that a window
    /// will open. Flip this to true and the warning would be dropped as unnecessary, and an
    /// unexplained pause reads to the player as a hang.
    @Test("only stores with a real silent installer claim one")
    func silentInstallerFlagMatchesReality() {
        #expect(GameStore.steam.descriptor.hasSilentInstaller, "Steam's installer takes /S")
        #expect(GameStore.battlenet.descriptor.hasSilentInstaller == false,
                "Blizzard ships no silent installer — setup must warn about the window")
    }

    /// `signsInOnce` drives the Accounts screen. A store whose sign-in happens inside a client
    /// window in the bottle cannot be signed in "once, account-wide", so the two must agree.
    @Test("account-level sign-in follows the auth style", arguments: GameStore.allCases)
    func signsInOnceFollowsAuthStyle(store: GameStore) {
        let d = store.descriptor
        #expect(d.signsInOnce == (d.authStyle == .cellarHeldToken))
        if d.authStyle == .none {
            #expect(d.signsInOnce == false, "\(store.rawValue) has nothing to sign in to")
        }
    }

    /// GOG is the store with no client in the bottle, and that is exactly why its sign-in is
    /// account-level. The two facts are linked, and the link is what the Accounts screen relies on.
    @Test("a store with no client in the bottle needs no in-client sign-in", arguments: GameStore.allCases)
    func clientlessStoresDoNotAskForAWindow(store: GameStore) {
        let d = store.descriptor
        if !d.installsClientInBottle {
            #expect(d.authStyle != .inClientWindow,
                    "\(store.rawValue) installs no client, so there is no window to sign in through")
        }
    }

    @Suite("Parsing a profile's store = \"…\"")
    struct Parsing {
        @Test("known spellings, including the ones people actually write",
              arguments: [("steam", GameStore.steam), ("Steam", .steam), ("  STEAM  ", .steam),
                          ("battlenet", .battlenet), ("battle.net", .battlenet),
                          ("blizzard", .battlenet), ("bnet", .battlenet),
                          ("gog", .gog), ("gog.com", .gog), ("gog-galaxy", .gog),
                          ("standalone", .standalone), ("none", .standalone),
                          ("direct", .standalone), ("drm-free", .standalone)])
        func recognisedSpellings(raw: String, expected: GameStore) {
            #expect(GameStore(profileValue: raw) == expected)
        }

        /// Returning nil rather than defaulting is the point: a typo must let the caller fall back
        /// deliberately, not silently classify a Battle.net game as a Steam one and drive the wrong
        /// pipeline at it.
        @Test("anything unrecognised is nil, never a guess",
              arguments: ["epic", "itch", "", "   ", "steamm", "gogo"])
        func unknownValuesAreNil(raw: String) {
            #expect(GameStore(profileValue: raw) == nil)
        }

        @Test("a missing value is nil")
        func missingValueIsNil() {
            #expect(GameStore(profileValue: nil) == nil)
        }
    }
}
