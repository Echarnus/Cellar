import CellarDomain
import CryptoKit
import Foundation

/// The game database, updated between app releases.
///
/// Adding or fixing a game is a TOML file, and waiting for a whole new Cellar to ship one was the
/// slowest part of it. So each release also publishes the `profiles/` set as one signed file,
/// `profiles.json`, and Cellar fetches it from the latest release, checks the signature against the
/// key compiled into this build, and keeps it in `Paths.registryProfiles` — searched after the
/// player's own profiles and before the ones bundled with the app.
///
/// Anything that doesn't verify is refused with a reason and nothing on disk changes, so the worst
/// a tampered download or a dead network can do is leave the database where it was. A downloaded
/// set made for an older Cellar than this one is ignored, so an app update never ends up under a
/// stale download.
public enum ProfileUpdates {

    /// The bundle as published: every profile's TOML by file name, and what it was made for.
    public struct ProfileBundle: Codable, Sendable {
        public var format: Int
        /// The Cellar release this set was published with. An older set never shadows a newer app.
        public var cellarVersion: String
        public var published: Date
        public var profiles: [String: String]
    }

    /// What is installed now, for Settings and `cellar profiles update`.
    public struct Installed: Codable, Sendable, Equatable {
        public var cellarVersion: String
        public var published: Date
        public var fetched: Date
        public var count: Int
    }

    public static let currentFormat = 1

    /// The Ed25519 public key profile bundles are signed with, base64 (raw 32 bytes). Empty until the
    /// release key exists (`Scripts/profiles-bundle.swift --generate-key`): a build without one
    /// refuses every download rather than trusting an unsigned one.
    public static let publicKey = "E/JvNBs4PKYI1fbjyx6l55yjGsRBLrvYM2Jx9dVuCCU="

    static let bundleURL = "https://github.com/Echarnus/Cellar/releases/latest/download/profiles.json"
    static var signatureURL: String { bundleURL + ".sig" }
    static let installedName = "installed.json"

    public enum Failure: Error, CustomStringConvertible, Equatable {
        case noKey
        case badSignature
        case unreadable(String)
        case olderThanApp(String)
        /// A genuine, signed set — but published before the one already installed. Refused so an old
        /// download served again cannot bring back a profile a later set fixed.
        case olderThanInstalled

        public var description: String {
            switch self {
            case .noKey:
                return "This build of Cellar has no key to check a game-database download with, so it keeps the database it shipped with."
            case .badSignature:
                return "The downloaded game database isn't signed by Cellar's key. It was refused and nothing changed."
            case .unreadable(let why):
                return "The downloaded game database couldn't be read (\(why)). Nothing changed."
            case .olderThanApp(let version):
                return "The published game database (from Cellar \(version)) is older than the one this app shipped with. Nothing changed."
            case .olderThanInstalled:
                return "The downloaded game database is older than the one Cellar already has. Nothing changed."
            }
        }
    }

    // MARK: - Checking a download

    /// Verify `data` against `signature` with `key` and decode it. Every check happens before
    /// anything is written.
    public static func verify(_ data: Data, signature: Data, key: String = publicKey) throws -> ProfileBundle {
        guard let raw = Data(base64Encoded: key), !key.isEmpty else { throw Failure.noKey }
        guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { throw Failure.noKey }
        guard publicKey.isValidSignature(signature, for: data) else { throw Failure.badSignature }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle: ProfileBundle
        do { bundle = try decoder.decode(ProfileBundle.self, from: data) } catch {
            throw Failure.unreadable("not a profile bundle")
        }
        guard bundle.format == currentFormat else { throw Failure.unreadable("format \(bundle.format)") }
        // File names only — a bundle never writes outside its own directory.
        for name in bundle.profiles.keys where !isSafeName(name) {
            throw Failure.unreadable("unexpected file name '\(name)'")
        }
        return bundle
    }

    /// A profile's file name is its slug, and the slug ends up in paths, bundle identifiers and the
    /// launcher scripts `AppBundle` writes. So a downloaded one is held to the slug alphabet the
    /// repository uses — lowercase letters, digits and `-` — rather than merely "no slashes".
    static func isSafeName(_ name: String) -> Bool {
        guard name.hasSuffix(".toml"), name.count <= 128 else { return false }
        let slug = name.dropLast(5)
        guard let first = slug.first, first != "-" else { return false }
        return slug.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    // MARK: - Installing it

    /// Replace the downloaded set with `bundle`. Written beside the old one and swapped in, so a
    /// failure partway leaves the previous set whole.
    public static func install(_ bundle: ProfileBundle, now: Date = Date(),
                               appVersion: String = CellarVersion.current) throws -> Installed {
        guard compare(bundle.cellarVersion, appVersion) != .orderedAscending else {
            throw Failure.olderThanApp(bundle.cellarVersion)
        }
        if let current = installed, bundle.published < current.published {
            throw Failure.olderThanInstalled
        }
        let fm = FileManager.default
        let target = Paths.registryProfiles
        let staging = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent)-incoming", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        for (name, text) in bundle.profiles {
            try text.write(to: staging.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let installed = Installed(cellarVersion: bundle.cellarVersion, published: bundle.published,
                                  fetched: now, count: bundle.profiles.count)
        try encoder.encode(installed).write(to: staging.appendingPathComponent(installedName))
        if fm.fileExists(atPath: target.path) {
            _ = try fm.replaceItemAt(target, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: target)
        }
        CellarLog.info(.app, "Game database updated: \(installed.count) profiles from Cellar \(installed.cellarVersion).")
        return installed
    }

    /// Fetch, verify and install the latest published set.
    @discardableResult
    public static func update() throws -> Installed {
        guard !publicKey.isEmpty else { throw Failure.noKey }
        let scratch = Paths.cache.appendingPathComponent("profiles-update", isDirectory: true)
        try? FileManager.default.removeItem(at: scratch)
        let bundleFile = try Downloader.fetch(bundleURL, to: scratch.appendingPathComponent("profiles.json"), showProgress: false)
        let signatureFile = try Downloader.fetch(signatureURL, to: scratch.appendingPathComponent("profiles.json.sig"), showProgress: false)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let data = try Data(contentsOf: bundleFile)
        let signatureText = try String(contentsOf: signatureFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let signature = Data(base64Encoded: signatureText) else { throw Failure.badSignature }
        return try install(try verify(data, signature: signature))
    }

    /// What the downloaded set is, if one is installed and this app will use it.
    public static var installed: Installed? {
        guard let data = try? Data(contentsOf: Paths.registryProfiles.appendingPathComponent(installedName)),
              let installed = try? decoder.decode(Installed.self, from: data),
              compare(installed.cellarVersion, CellarVersion.current) != .orderedAscending else { return nil }
        return installed
    }

    /// Whether `Paths.profileSearchPaths` should include the downloaded set: only one made for this
    /// Cellar or a newer one.
    static var isUsable: Bool { installed != nil }

    /// Numeric SemVer comparison of the `MAJOR.MINOR.PATCH` part; a suffix is ignored.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func parts(_ v: String) -> [Int] {
            let core = v.split(separator: "-").first.map(String.init) ?? v
            return core.split(separator: ".").map { Int($0) ?? 0 } + [0, 0, 0]
        }
        let (x, y) = (parts(a), parts(b))
        for i in 0..<3 where x[i] != y[i] { return x[i] < y[i] ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
