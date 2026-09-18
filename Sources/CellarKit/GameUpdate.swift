import Foundation

/// Keeping a game Cellar downloaded itself on the build Steam is serving.
///
/// A copy Steam installed is Steam's to update — it does that on its own every time it starts. A
/// copy Cellar fetched with DepotDownloader is invisible to Steam (there is no appmanifest for it),
/// so nobody would ever update it: the game would sit on the build it was downloaded at until a
/// patch made it refuse to go online. This is the part that notices and catches it up.
///
/// **Steam is the source of truth, both sides.** What is installed is what DepotDownloader recorded
/// in `.DepotDownloader/depot.config` when the download finished; what is current is what Steam
/// hands the same account for the same app today (`-manifest-only`, which moves no game files).
/// They are compared depot by depot, by manifest id — no version strings, no guessing from dates.
public enum GameUpdates {
    /// What Cellar knows about whether a downloaded game is current.
    public enum State: Sendable, Equatable {
        /// Steam confirmed every depot matches what is on disk, at `checked`.
        case upToDate(checked: Date)
        /// Steam is serving a newer build than the one on disk.
        case available(checked: Date)
        /// Not asked yet, or the question could not be answered. Never shown as "up to date": a
        /// check that did not happen is not a check that passed.
        case unknown(String)
    }

    /// Whether Cellar is the one keeping this copy current: a Steam app it downloaded itself, and
    /// not one Steam's own library also has (Steam updates those, and Play goes through Steam).
    public static func managesUpdates(_ plan: GamePlan) -> Bool {
        guard let appID = plan.appID, DepotManifests.installed(in: plan.depotGameDir) != nil else { return false }
        return !SteamBottle.isGameInstalled(in: plan.prefix, appID: appID)
    }

    /// The last answer, re-read against what is on disk now — so an update that has just finished
    /// reads as up to date without asking Steam again. No network: the library calls this on every
    /// refresh. Nil when Cellar does not manage this copy's updates.
    public static func cachedState(_ plan: GamePlan) -> State? {
        guard managesUpdates(plan), let installed = DepotManifests.installed(in: plan.depotGameDir) else { return nil }
        guard let record = UpdateRecord.load(slug: plan.slug) else { return .unknown("not checked yet") }
        return record.state(against: installed)
    }

    /// Ask Steam which build is current and compare it with the copy on disk. Remembers the answer
    /// for `cachedState`. A few seconds and a few megabytes of manifest; no game files move.
    @discardableResult
    public static func check(_ plan: GamePlan, timeout: TimeInterval = 90) -> State {
        guard let appID = plan.appID,
              let installed = DepotManifests.installed(in: plan.depotGameDir) else {
            return .unknown("Cellar didn't download this copy, so it has nothing to compare")
        }
        guard let credentials = SteamAccount.credentials else {
            return .unknown("not signed in to Steam")
        }
        switch DepotTool.latestManifests(appID: appID, credentials: credentials, timeout: timeout) {
        case .unknown(let why):
            CellarLog.info(.install, "Couldn't check \(plan.name) for updates: \(why)", subject: plan.slug)
            return .unknown(why)
        case .manifests(let latest):
            let record = UpdateRecord(checked: Date(), latest: latest)
            record.save(slug: plan.slug)
            let state = record.state(against: installed)
            let verdict: String
            if case .available = state { verdict = "a newer build is out" } else { verdict = "up to date" }
            CellarLog.info(.install, "Update check for \(plan.name): \(verdict)", subject: plan.slug)
            return state
        }
    }

    /// How long an answer stands before the app asks Steam again — and how long "Up to date" may be
    /// said without its age beside it.
    public static let recheckInterval: TimeInterval = 6 * 60 * 60

    /// Whether `cachedState` is recent enough that asking again would only cost the player time.
    public static func isFresh(_ state: State?, within interval: TimeInterval, now: Date = Date()) -> Bool {
        switch state {
        case .upToDate(let checked), .available(let checked): return now.timeIntervalSince(checked) < interval
        case .unknown, nil: return false
        }
    }

    /// Why an update did not finish — and, the part that matters, whether the files were touched.
    public enum UpdateFailure: Error, LocalizedError, Equatable {
        /// Nothing on disk changed: the build there is exactly as intact as before.
        case notStarted(String)
        /// Files were being replaced when it stopped. The game is in no known state until it resumes.
        case partial(String)
        /// Another download is already writing into this game's folder.
        case alreadyDownloading

        public var errorDescription: String? {
            switch self {
            case .notStarted(let why), .partial(let why): return why
            case .alreadyDownloading: return "another download is already writing into this game's folder"
            }
        }
    }

    /// Bring the copy on disk up to Steam's current build.
    ///
    /// DepotDownloader is pointed at the same directory it downloaded into: it diffs the manifest it
    /// recorded there against the new one and fetches only the chunks that changed, so a patch costs
    /// a patch, not the whole game. It records a depot's new manifest only once that depot is
    /// through, so an interrupted update is resumed by the next run rather than counted as done —
    /// and `depot.config` is read back afterwards, so "updated" never rests on an exit code alone.
    public static func apply(_ plan: GamePlan, progress: (String) -> Void = { _ in },
                             phase: (InstallProgress) -> Void = { _ in }) throws {
        guard let appID = plan.appID else {
            throw UpdateFailure.notStarted("profile '\(plan.slug)' has no steam_appid")
        }
        guard !DepotTool.isDownloading(into: plan.depotGameDir) else { throw UpdateFailure.alreadyDownloading }
        guard let credentials = SteamAccount.credentials else {
            throw UpdateFailure.notStarted("not signed in to Steam — cellar steam login")
        }
        CellarLog.info(.install, "Updating \(plan.name) (AppID \(appID)).", subject: plan.slug)
        phase(InstallProgress(.updating))
        // DepotDownloader prints a percentage per file it writes, so the first one is the moment the
        // copy on disk stops being the old build.
        var touched = false
        do {
            try withoutActuallyEscaping(progress) { report in
                try withoutActuallyEscaping(phase) { phase in
                    try DepotTool.fetch(appID: appID, into: plan.depotGameDir, credentials: credentials) { line in
                        if let fraction = DepotProgress.fraction(in: line) {
                            touched = true
                            phase(InstallProgress(.updating, fraction: fraction))
                        }
                        report(line)
                    }
                }
            }
        } catch {
            let why = CellarLog.describe(error)
            throw touched ? UpdateFailure.partial(why) : UpdateFailure.notStarted(why)
        }
        if let installed = DepotManifests.installed(in: plan.depotGameDir),
           let record = UpdateRecord.load(slug: plan.slug),
           case .available = record.state(against: installed) {
            throw UpdateFailure.partial("Steam's download ended before every part of the game was current")
        }
        CellarLog.info(.install, "\(plan.name) is up to date.", subject: plan.slug)
    }
}

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

/// Just enough protobuf to read `depot.config`: varints, and skipping what it doesn't need.
private struct ProtoReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { index >= bytes.count }

    mutating func varint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }

    mutating func tag() -> (field: UInt64, wire: UInt64)? {
        guard let key = varint() else { return nil }
        return (key >> 3, key & 0x7)
    }

    mutating func lengthDelimited() -> [UInt8]? {
        guard let length = varint(), let count = Int(exactly: length),
              count <= bytes.count - index else { return nil }
        defer { index += count }
        return Array(bytes[index..<index + count])
    }

    mutating func skip(wire: UInt64) -> Bool {
        switch wire {
        case 0: return varint() != nil
        case 1: guard bytes.count - index >= 8 else { return false }; index += 8; return true
        case 2: return lengthDelimited() != nil
        case 5: guard bytes.count - index >= 4 else { return false }; index += 4; return true
        default: return false
        }
    }
}
