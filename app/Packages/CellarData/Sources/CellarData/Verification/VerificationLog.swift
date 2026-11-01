import CellarDomain
import Foundation

/// Reading only what a log gained during a verification run, so a crash or a refused sign-in from
/// yesterday is never counted against today's run.
public enum VerificationLog {
    /// The size of `url` now: where the run's own lines will start.
    public static func mark(_ url: URL) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.uint64Value ?? 0
    }

    /// What `url` holds after `mark`. A log that was started afresh since (it is now shorter than
    /// the mark) is read whole, because all of it is new.
    public static func text(of url: URL, since mark: UInt64) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size >= mark ? mark : 0)
        guard let data = try? handle.readToEnd() else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
