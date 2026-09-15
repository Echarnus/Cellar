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
