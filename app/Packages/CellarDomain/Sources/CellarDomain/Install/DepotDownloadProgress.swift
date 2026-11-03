import Foundation

/// One bar for a whole Steam download, read from DepotDownloader's output line by line.
///
/// DepotDownloader's ` 12.34% file` line is the share of **one depot**, not the game (#309). A
/// game with DLC or language depots runs them back to back, so reading that number straight made
/// the bar fill to 100% once per depot — Dark Souls III looked like it was downloading three
/// times. This follows the run instead:
///
/// - `Processing depot N`, then `Manifest M (…)`: the depots this run will fetch, in the order it
///   fetches them, and each one's size from the manifest DepotDownloader just saved (`size`).
/// - `Downloading depot N`: the depot whose percentage the following lines are.
/// - `Depot N - Downloaded …`: that depot is done, whatever its last percentage said.
/// - `Validating <file>`: a file already on disk is being checked, not fetched. That is what a
///   resumed download does first, and the bar says so (`InstallPhase.checkingDownload`) instead of
///   calling it downloading.
///
/// The bar is each depot's share weighted by its size, and it never goes backwards. A depot whose
/// size could not be read gets an equal share of the depots, still one bar — a weight that is only
/// approximate is better than a bar that starts over.
public struct DepotDownloadProgress: Sendable {
    /// The phase the bar shows while files are being fetched: `.downloading` for an install,
    /// `.updating` for an update.
    public let phase: InstallPhase

    private var depots: [UInt32] = []
    private var sizes: [UInt32: UInt64] = [:]
    private var shares: [UInt32: Double] = [:]
    /// The depot whose manifest is being read (after `Processing`), then the one downloading.
    private var current: UInt32?
    /// Files reported as being checked whose result has not come yet.
    private var checking: Set<String> = []
    private var checked = false
    private var reported = 0.0

    public init(phase: InstallPhase = .downloading) {
        self.phase = phase
    }

    /// Whether anything on disk has been checked rather than fetched this run.
    public var resumed: Bool { checked }

    /// The progress to show after `line`, or nil when the line changes nothing a bar could draw.
    /// `size` gives a depot's total size from its manifest, when it can be read.
    public mutating func read(_ line: String,
                              size: (_ depot: UInt32, _ manifest: UInt64) -> UInt64?) -> InstallProgress? {
        let text = line.drop { $0 == " " }
        if let depot = Self.number(after: "Processing depot ", in: text) {
            if !depots.contains(depot) { depots.append(depot) }
            current = depot
            return nil
        }
        if let manifest = Self.wideNumber(after: "Manifest ", in: text), let depot = current {
            if let bytes = size(depot, manifest) { sizes[depot] = bytes }
            return nil
        }
        if text.hasPrefix("Downloading depot "), !text.hasSuffix("manifest"),
           let depot = Self.number(after: "Downloading depot ", in: text) {
            if !depots.contains(depot) { depots.append(depot) }
            current = depot
            checking.removeAll()
            return nil
        }
        if let depot = Self.number(after: "Depot ", in: text), text.contains(" - Downloaded ") {
            shares[depot] = 1
            return report()
        }
        if text.hasPrefix("Validating ") {
            checking.insert(String(text.dropFirst("Validating ".count)))
            checked = true
            return InstallProgress(.checkingDownload, fraction: reported)
        }
        guard let fraction = DepotProgress.fraction(in: line) else { return nil }
        // No depot named yet (an older or unexpected output): the one percentage there is.
        let depot = current ?? 0
        shares[depot] = max(shares[depot] ?? 0, fraction)
        // The file after the percentage: one that was just checked and found whole is still part
        // of the check; anything else was fetched.
        let file = text.firstIndex(of: "%").map { String(text[text.index(after: $0)...].drop { $0 == " " }) }
        let stillChecking = file.map { checking.remove($0) != nil } ?? false
        return report(checking: stillChecking)
    }

    /// The whole game's share so far, never less than what was shown before.
    public var fraction: Double { reported }

    private mutating func report(checking: Bool = false) -> InstallProgress {
        reported = max(reported, overall)
        return InstallProgress(checking ? .checkingDownload : phase, fraction: reported)
    }

    private var overall: Double {
        guard !depots.isEmpty else { return shares[0] ?? 0 }
        let known = depots.compactMap { sizes[$0] }
        var weights = known.map { Double($0) }
        // A size that could not be read: an equal share for every depot, rather than a guess mixed
        // with real numbers. (An empty depot weighs nothing, which is right.)
        if known.count != depots.count || weights.reduce(0, +) == 0 {
            weights = depots.map { _ in 1 }
        }
        let total = weights.reduce(0, +)
        let done = zip(depots, weights).reduce(0.0) { $0 + (shares[$1.0] ?? 0) * $1.1 }
        return min(done / total, 1)
    }

    /// The decimal number right after `prefix` at the start of `text`.
    static func number(after prefix: String, in text: Substring) -> UInt32? {
        wideNumber(after: prefix, in: text).flatMap { UInt32(exactly: $0) }
    }

    static func wideNumber(after prefix: String, in text: Substring) -> UInt64? {
        guard text.hasPrefix(prefix) else { return nil }
        let digits = text.dropFirst(prefix.count).prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return UInt64(digits)
    }
}
