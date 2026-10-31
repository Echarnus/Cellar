// Builds the signed game-database bundle a release publishes (`ProfileUpdates` in CellarData).
//
//   swift Scripts/profiles-bundle.swift VERSION OUT_DIR
//       writes OUT_DIR/profiles.json from profiles/*.toml, and OUT_DIR/profiles.json.sig when
//       PROFILES_SIGNING_KEY (base64 raw Ed25519 private key) is set in the environment.
//   swift Scripts/profiles-bundle.swift --generate-key
//       prints a new key pair, once. The private key goes into the `release` environment as the
//       secret PROFILES_SIGNING_KEY; the public key into ProfileUpdates.publicKey. Replacing the key
//       later strands every installed copy on the database it shipped with.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
if args == ["--generate-key"] {
    let key = Curve25519.Signing.PrivateKey()
    print("PROFILES_SIGNING_KEY (secret, release environment): \(key.rawRepresentation.base64EncodedString())")
    print("ProfileUpdates.publicKey (commit it):              \(key.publicKey.rawRepresentation.base64EncodedString())")
    exit(0)
}
if args == ["--public-key"] {
    // The private key on stdin (never argv), its public half on stdout. Scripts/signing-keys.sh
    // uses this to write ProfileUpdates.publicKey from the key in the keychain.
    let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let raw = Data(base64Encoded: text), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("stdin is not a base64 raw Ed25519 private key")
    }
    print(key.publicKey.rawRepresentation.base64EncodedString())
    exit(0)
}
guard args.count == 2 else { fail("usage: swift Scripts/profiles-bundle.swift VERSION OUT_DIR | --generate-key | --public-key") }
let version = args[0].hasPrefix("v") ? String(args[0].dropFirst()) : args[0]
let out = URL(fileURLWithPath: args[1], isDirectory: true)

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
// The profile database is at the top of the repository (`profiles/`), one level above `app/`.
let profiles = [root.appendingPathComponent("profiles", isDirectory: true),
                root.deletingLastPathComponent().appendingPathComponent("profiles", isDirectory: true)]
    .first { FileManager.default.fileExists(atPath: $0.path) } ?? root.appendingPathComponent("profiles", isDirectory: true)
let files = (try? FileManager.default.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil)) ?? []
var contents: [String: String] = [:]
for file in files where file.pathExtension == "toml" {
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { fail("unreadable: \(file.lastPathComponent)") }
    contents[file.lastPathComponent] = text
}
guard !contents.isEmpty else { fail("no profiles in \(profiles.path)") }

struct ProfileBundle: Encodable {
    let format: Int
    let cellarVersion: String
    let published: Date
    let profiles: [String: String]
}
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(ProfileBundle(format: 1, cellarVersion: version, published: Date(), profiles: contents))
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try data.write(to: out.appendingPathComponent("profiles.json"))
print("profiles.json: \(contents.count) profiles for Cellar \(version)")

if let secret = ProcessInfo.processInfo.environment["PROFILES_SIGNING_KEY"], !secret.isEmpty {
    guard let raw = Data(base64Encoded: secret), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("PROFILES_SIGNING_KEY is not a base64 raw Ed25519 private key")
    }
    let signature = try key.signature(for: data)
    try (signature.base64EncodedString() + "\n").write(to: out.appendingPathComponent("profiles.json.sig"),
                                                       atomically: true, encoding: .utf8)
    print("profiles.json.sig: signed")
} else {
    print("PROFILES_SIGNING_KEY not set: unsigned, so no installed Cellar will accept it")
}
