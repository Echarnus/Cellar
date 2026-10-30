import CryptoKit
import Foundation
import Testing
@testable import CellarKit

/// The game database fetched between releases: accepted only when Cellar's key signed it, and
/// never shadowing a newer app's own profiles.
@Suite(.serialized)
struct ProfileUpdatesTests {

    let key = Curve25519.Signing.PrivateKey()
    var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }

    func bundle(version: String = "99.0.0", profiles: [String: String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(ProfileUpdates.ProfileBundle(format: 1, cellarVersion: version,
                                                               published: Date(timeIntervalSince1970: 1_800_000_000),
                                                               profiles: profiles))
    }

    @Test("A bundle signed with the key is accepted; a changed byte or another key is refused")
    func signature() throws {
        let data = try bundle(profiles: ["fixture.toml": "[game]\nname = \"X\"\n"])
        let signature = try key.signature(for: data)
        let accepted = try ProfileUpdates.verify(data, signature: signature, key: publicKey)
        #expect(accepted.profiles.count == 1)

        var tampered = data
        tampered[tampered.count / 2] ^= 0x01
        #expect(throws: ProfileUpdates.Failure.badSignature) {
            try ProfileUpdates.verify(tampered, signature: signature, key: publicKey)
        }
        let stranger = try Curve25519.Signing.PrivateKey().signature(for: data)
        #expect(throws: ProfileUpdates.Failure.badSignature) {
            try ProfileUpdates.verify(data, signature: stranger, key: publicKey)
        }
        #expect(throws: ProfileUpdates.Failure.noKey) {
            try ProfileUpdates.verify(data, signature: signature, key: "")
        }
    }

    @Test("A signed bundle still can't write outside its own folder")
    func fileNames() throws {
        let data = try bundle(profiles: ["../settings.toml": "x"])
        #expect(throws: ProfileUpdates.Failure.self) {
            try ProfileUpdates.verify(data, signature: try key.signature(for: data), key: publicKey)
        }
    }

    @Test("An installed bundle is searched before the bundled profiles; an older one is refused")
    func installs() throws {
        TestHome.ensure()
        defer { try? FileManager.default.removeItem(at: Paths.registryProfiles) }
        let slug = "registry-\(UUID().uuidString.prefix(8))".lowercased()
        let data = try bundle(profiles: ["\(slug).toml": "[game]\nname = \"From The Registry\"\nstore = \"steam\"\n"])
        let installed = try ProfileUpdates.install(try ProfileUpdates.verify(data, signature: try key.signature(for: data), key: publicKey))
        #expect(installed.count == 1)
        #expect(ProfileUpdates.installed?.cellarVersion == "99.0.0")
        #expect(ProfileUpdates.installed?.count == 1)
        #expect(Paths.profileSearchPaths.contains(Paths.registryProfiles))
        #expect(try Game.plan(slug: slug).name == "From The Registry")

        let old = try bundle(version: "0.0.1", profiles: ["a.toml": "x"])
        #expect(throws: ProfileUpdates.Failure.olderThanApp("0.0.1")) {
            try ProfileUpdates.install(try ProfileUpdates.verify(old, signature: try key.signature(for: old), key: publicKey))
        }
        #expect(try Game.plan(slug: slug).name == "From The Registry", "a refused bundle changes nothing")
    }

    @Test("Versions compare by number, not by text")
    func versions() {
        #expect(ProfileUpdates.compare("0.10.0", "0.9.9") == .orderedDescending)
        #expect(ProfileUpdates.compare("1.0.0", "1.0.0-beta") == .orderedSame)
        #expect(ProfileUpdates.compare("0.2", "0.2.1") == .orderedAscending)
    }
}
