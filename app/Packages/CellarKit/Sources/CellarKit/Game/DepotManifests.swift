import CellarDomain
import Foundation

/// Reading DepotDownloader's own records of which build is where.
public enum DepotManifests {
    /// The manifest DepotDownloader installed for each depot in `directory`, or nil when it has
    /// never finished a download there.
    public static func installed(in directory: URL) -> [UInt32: UInt64]? {
        let config = directory.appendingPathComponent(".DepotDownloader/depot.config")
        guard let data = try? Data(contentsOf: config) else { return nil }
        guard let manifests = decodeDepotConfig(data), !manifests.isEmpty else { return nil }
        return manifests
    }

    /// `depot.config` is DepotDownloader's `DepotConfigStore` — a protobuf message whose field 1 is
    /// `map<uint32 depot, uint64 manifest>` — written through .NET's `DeflateStream`, i.e. raw
    /// DEFLATE with no zlib header. Anything that does not parse is nil, never a guess.
    static func decodeDepotConfig(_ data: Data) -> [UInt32: UInt64]? {
        guard let raw = try? (data as NSData).decompressed(using: .zlib) as Data else { return nil }
        return decodeManifestMap(raw)
    }

    /// The protobuf half, split out so it can be tested without a compressor.
    static func decodeManifestMap(_ bytes: Data) -> [UInt32: UInt64]? {
        var reader = ProtoReader(Array(bytes))
        var result: [UInt32: UInt64] = [:]
        while !reader.isAtEnd {
            guard let (field, wire) = reader.tag() else { return nil }
            if field == 1, wire == 2 {
                guard let entry = reader.lengthDelimited() else { return nil }
                var inner = ProtoReader(entry)
                var key: UInt64?
                var value: UInt64?
                while !inner.isAtEnd {
                    guard let (f, w) = inner.tag() else { return nil }
                    switch (f, w) {
                    case (1, 0): key = inner.varint()
                    case (2, 0): value = inner.varint()
                    default: guard inner.skip(wire: w) else { return nil }
                    }
                }
                // proto3 leaves a zero out, so a missing value is 0 rather than a malformed entry.
                guard let key, let depot = UInt32(exactly: key) else { return nil }
                result[depot] = value ?? 0
            } else if !reader.skip(wire: wire) {
                return nil
            }
        }
        return result
    }

    /// Follows a `-manifest-only` run line by line and collects which manifest Steam serves for
    /// each depot. Knows when it has them all, so the run can be stopped before it bothers to
    /// download manifest bodies it does not need.
    public struct Listing: Sendable, Equatable {
        /// The depots Steam handed keys for — the ones this run will report on.
        public private(set) var expected: Set<UInt32> = []
        public private(set) var manifests: [UInt32: UInt64] = [:]
        /// A reason no answer will come, once the output has said so.
        public private(set) var failure: String?
        private var current: UInt32?

        public init() {}

        public var isComplete: Bool {
            failure != nil || (!expected.isEmpty && expected.isSubset(of: Set(manifests.keys)))
        }

        public mutating func read(_ line: String) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if let depot = Self.number(after: "Got depot key for ", in: text), text.hasSuffix("result: OK") {
                expected.insert(UInt32(clamping: depot))
            } else if let depot = Self.number(after: "Processing depot ", in: text) {
                current = UInt32(clamping: depot)
            } else if let depot = Self.number(after: "Got manifest request code for depot ", in: text),
                      let manifest = Self.number(after: ", manifest ", in: text) {
                manifests[UInt32(clamping: depot)] = manifest
            } else if let manifest = Self.number(after: "Manifest ", in: text), text.hasPrefix("Manifest "),
                      let current {
                manifests[current] = manifest
            } else if text.contains("is not available from this account") {
                failure = "Steam says this account doesn't own it"
            } else if text.contains("Access token was rejected") {
                failure = "your Steam sign-in has expired"
            } else if text.contains("Couldn't find any depots to download") {
                failure = "Steam lists no Windows depot for this app"
            }
        }

        /// The run digits that follow `marker`, if `marker` is in the line.
        static func number(after marker: String, in text: String) -> UInt64? {
            guard let range = text.range(of: marker) else { return nil }
            let digits = text[range.upperBound...].prefix { $0.isASCII && $0.isNumber }
            return UInt64(digits)
        }
    }
}
