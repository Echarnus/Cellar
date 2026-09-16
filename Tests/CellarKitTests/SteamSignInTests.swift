import Compression
import Foundation
import Testing
@testable import CellarKit

/// The Steam QR sign-in has to learn *who* signed in, or every later download asks again. A plain
/// approval in the Steam mobile app makes DepotDownloader save a token but print no line naming the
/// account — so the name is read from the token store, and these pin how.
struct SteamSignInTests {

    // MARK: - Reading the store

    @Test("Account names are read from a DepotDownloader store, and only the names")
    func readsAccountNames() {
        let store = Self.store(tokens: [("kennethdc", "eyJ-refresh-token"), ("second", "other")],
                               guard: [("kennethdc", "guard")])
        #expect(DepotAccountStore.accountNames(inCompressed: store) == ["kennethdc", "second"])
    }

    @Test("A store with no tokens, or that doesn't parse, yields no names")
    func unreadableStoreHasNoNames() {
        #expect(DepotAccountStore.accountNames(inCompressed: Self.store(tokens: [], guard: [])).isEmpty)
        #expect(DepotAccountStore.accountNames(inCompressed: Data()).isEmpty)
        #expect(DepotAccountStore.accountNames(inCompressed: Data("not deflate".utf8)).isEmpty)
        let full = Self.store(tokens: [("kennethdc", "token")], guard: [])
        #expect(DepotAccountStore.accountNames(inCompressed: full.prefix(full.count / 2)).count <= 1)
    }

    @Test("The QR sign-in asks Steam for a persistent session")
    func qrSessionIsPersistent() {
        // Without -remember-password DepotDownloader sets IsPersistentSession = false, and Steam's
        // short-lived token was refused with AccessDenied minutes after a working sign-in.
        #expect(DepotTool.Credentials.qr.arguments == ["-qr", "-remember-password"])
    }

    @Test("A store emptied by a refused token holds no session")
    func emptiedStoreIsNoSession() {
        // What DepotDownloader writes back after `Access token was rejected`: the file survives,
        // the token does not. Only names count as a session.
        let emptied = Self.store(tokens: [], guard: [])
        #expect(!emptied.isEmpty)
        #expect(DepotAccountStore.accountNames(inCompressed: emptied).isEmpty)
    }

    @Test("A session Steam refused stays 'expired', named, even though the token is already gone")
    func rejectionOutranksTheEmptiedStore() {
        var record = SteamAccount.SignIn(accountName: "kennethdc", signedInAt: Date(), lastUsedAt: Date())
        #expect(SteamAccount.state(record: record, storedAccountNames: ["kennethdc"])
                == .signedIn(account: "kennethdc", days: 0, aging: false))
        // A store without this account — emptied out of band — is no session.
        #expect(SteamAccount.state(record: record, storedAccountNames: []) == .signedOut)
        #expect(SteamAccount.state(record: record, storedAccountNames: ["someoneelse"]) == .signedOut)
        // DepotDownloader deletes the token before printing the rejection, so the store is empty by
        // the time Cellar notes it. The player must still be told whose session ended, and why.
        record.rejectedAt = Date()
        record.rejectionReason = "accessdenied"
        #expect(SteamAccount.state(record: record, storedAccountNames: [])
                == .expired(account: "kennethdc", reason: "accessdenied"))
        #expect(SteamAccount.state(record: nil, storedAccountNames: ["kennethdc"]) == .signedOut)
    }

    // MARK: - Choosing the account

    @Test("A name that gained a token during the sign-in is the one that signed in")
    func newNameWins() {
        let start = Date()
        let stores = [(names: ["old", "kennethdc"], modified: start.addingTimeInterval(20))]
        #expect(SteamAccount.accountName(storedSince: start, previously: ["old"], stores: stores) == "kennethdc")
    }

    @Test("Signing in again as the same person is recognised when the store is unambiguous")
    func sameAccountAgain() {
        let start = Date()
        let stores = [(names: ["kennethdc"], modified: start.addingTimeInterval(20))]
        #expect(SteamAccount.accountName(storedSince: start, previously: ["KennethDC"], stores: stores) == "kennethdc")
    }

    @Test("An untouched store is not a sign-in, and an ambiguous one is never guessed")
    func noApprovalNoName() {
        let start = Date()
        let untouched = [(names: ["kennethdc"], modified: start.addingTimeInterval(-60))]
        #expect(SteamAccount.accountName(storedSince: start, previously: [], stores: untouched) == nil)
        let ambiguous = [(names: ["a", "b"], modified: start.addingTimeInterval(5))]
        #expect(SteamAccount.accountName(storedSince: start, previously: ["a", "b"], stores: ambiguous) == nil)
    }

    // MARK: - Progress after the phone approves

    @Test("The approval is seen as soon as Steam logs the session on, with or without the success line")
    func approvalIsRecognised() {
        // The exact sentences DepotDownloader 3.4.0 prints (Steam3Session.cs).
        #expect(SteamAccount.signInPhase(after: "Got 23 licenses for account!") == .approved)
        #expect(SteamAccount.signInPhase(after: "  Unable to get license list: Timeout ") == .approved)
        #expect(SteamAccount.signInPhase(
            after: "  Success! Next time you can login with -username kennethdc -remember-password instead of -qr.")
            == .approved)
        #expect(SteamAccount.isSessionEstablished("Got 0 licenses for account!"))
    }

    @Test("The CLI's own sentences move the panel on, and QR noise does not")
    func laterPhases() {
        #expect(SteamAccount.signInPhase(after: "Signed in as kennethdc.") == .signedIn)
        #expect(SteamAccount.signInPhase(after: "  Asking Steam about game 2 of 5…")
                == .checkingLibrary("Asking Steam about game 2 of 5…"))
        for line in ["  Use the Steam Mobile App to sign in with this QR code:", "  ██▀▀██  ▄▄",
                     "Connecting to Steam3... Done!", "Logging in with QR code...", ""] {
            #expect(SteamAccount.signInPhase(after: line) == nil, "\(line)")
            #expect(!SteamAccount.isSessionEstablished(line))
        }
    }

    // MARK: - Fixture

    /// An `AccountSettingsStore` the way protobuf-net writes it through .NET's `DeflateStream`:
    /// field 2 content-server penalties, field 4 login tokens, field 5 guard data — raw deflate.
    static func store(tokens: [(String, String)], guard guardData: [(String, String)]) -> Data {
        var message = Data()
        message += field(2, entry(string: "cm.steampowered.com", int: 3))
        for (name, token) in tokens { message += field(4, entry(name, token)) }
        for (name, value) in guardData { message += field(5, entry(name, value)) }
        return deflate(message)
    }

    private static func varint(_ value: UInt64) -> Data {
        var v = value, out = Data()
        repeat {
            var b = UInt8(v & 0x7f); v >>= 7
            if v != 0 { b |= 0x80 }
            out.append(b)
        } while v != 0
        return out
    }

    private static func field(_ number: UInt64, _ payload: Data) -> Data {
        varint(number << 3 | 2) + varint(UInt64(payload.count)) + payload
    }

    private static func entry(_ key: String, _ value: String) -> Data {
        field(1, Data(key.utf8)) + field(2, Data(value.utf8))
    }

    private static func entry(string key: String, int value: UInt64) -> Data {
        field(1, Data(key.utf8)) + varint(2 << 3 | 0) + varint(value)
    }

    private static func deflate(_ data: Data) -> Data {
        let capacity = data.count + 1024
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        return out.prefix(written)
    }
}
