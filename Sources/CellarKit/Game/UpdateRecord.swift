import CellarDomain
import Foundation

/// The last thing Steam said was current for one game, kept so the library can show it without
/// asking again. Stored as manifest ids, not as a verdict: the verdict is recomputed against
/// `depot.config` every time, so it can never go stale in the "still says update available after
/// updating" direction.
struct UpdateRecord: Codable, Equatable {
    var checked: Date
    /// depot id → manifest id, as strings (JSON object keys have to be).
    var latest: [String: String]

    init(checked: Date, latest: [UInt32: UInt64]) {
        self.checked = checked
        self.latest = Dictionary(uniqueKeysWithValues: latest.map { ("\($0.key)", "\($0.value)") })
    }

    func state(against installed: [UInt32: UInt64]) -> GameUpdates.State {
        let behind = latest.contains { depot, manifest in
            guard let id = UInt32(depot) else { return false }
            return installed[id].map { "\($0)" } != manifest
        }
        return behind ? .available(checked: checked) : .upToDate(checked: checked)
    }

    static func url(slug: String) -> URL {
        Paths.cache.appendingPathComponent("updates/\(slug).json")
    }

    static func load(slug: String) -> UpdateRecord? {
        guard let data = try? Data(contentsOf: url(slug: slug)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UpdateRecord.self, from: data)
    }

    func save(slug: String) {
        let url = Self.url(slug: slug)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
