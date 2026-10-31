import CellarDomain
import Foundation

/// Wine's own test for "this prefix needs updating", made without starting Wine.
///
/// `wineboot` writes the modification time of the `wine.inf` it applied into
/// `<prefix>/.update-timestamp`; every Wine process started afterwards compares the two and rebuilds
/// the prefix when they differ. The file may also say `disable`, which turns the check off.
public enum PrefixFreshness {
    public static func needsUpdate(prefix: URL, wineInf: URL) -> Bool {
        // No registry means no prefix yet — building one is `initializePrefix`'s job, not an update.
        guard FileManager.default.fileExists(atPath: prefix.appendingPathComponent("system.reg").path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: wineInf.path),
              let modified = attributes[.modificationDate] as? Date else { return false }
        guard let recorded = try? String(contentsOf: prefix.appendingPathComponent(".update-timestamp"),
                                         encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return true }
        if recorded == "disable" { return false }
        return recorded != String(Int(modified.timeIntervalSince1970))
    }
}
