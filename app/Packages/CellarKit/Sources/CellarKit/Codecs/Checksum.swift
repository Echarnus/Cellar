import CellarDomain
import CryptoKit
import Foundation

/// SHA-256 pins for what Cellar downloads and then runs.
///
/// The runners and DepotDownloader are other projects' GitHub release assets. HTTPS proves they
/// came from GitHub, not that they are the files this build was tested with: a release owner (or
/// whoever takes over their account) can replace an asset under the same URL. So each one is pinned
/// to the digest it had when it was added, and a file that does not match is deleted and refused
/// before anything is unpacked or made executable.
public enum Checksum {

    public enum Failure: Error, CustomStringConvertible, Equatable {
        case mismatch(what: String, expected: String, actual: String)
        case unreadable(String)

        public var description: String {
            switch self {
            case .mismatch(let what, let expected, let actual):
                return "The download of \(what) isn't the file this version of Cellar was built for "
                    + "(expected SHA-256 \(expected.prefix(12))…, got \(actual.prefix(12))…). It was deleted and "
                    + "nothing was installed. Try again; if it keeps happening, the file was changed at its "
                    + "source — please report it."
            case .unreadable(let what):
                return "Cellar couldn't read the download of \(what) to check it. Nothing was installed."
            }
        }
    }

    /// Lowercase hex SHA-256 of the file at `url`, read in 1 MiB chunks so a multi-GB archive never
    /// sits in memory whole.
    public static func sha256(of url: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw Failure.unreadable(url.lastPathComponent)
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Whether `pin` is a well-formed digest: 64 lowercase hex characters.
    public static func isWellFormed(_ pin: String) -> Bool {
        pin.count == 64 && pin.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    /// Throw, and delete the file, unless it hashes to `sha256`. A cached copy is checked the same
    /// way as a fresh one, so a file swapped in the cache is refused too.
    public static func verify(_ file: URL, sha256 expected: String, what: String) throws {
        let actual = try sha256(of: file)
        guard isWellFormed(expected), actual == expected else {
            try? FileManager.default.removeItem(at: file)
            CellarLog.error(.runner, "Refused \(what): SHA-256 \(actual) does not match the pinned \(expected).")
            throw Failure.mismatch(what: what, expected: expected, actual: actual)
        }
    }
}
