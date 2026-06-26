import Foundation

public struct RunnerInfo {
    public let id: String
    public let url: URL
}

/// Manages installed Wine runners. Installation (downloading prebuilt LGPL Wine builds)
/// lands in Phase 1; for now this enumerates what's present.
public enum RunnerManager {
    public static func list() throws -> [RunnerInfo] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Paths.runners.path) else { return [] }
        let entries = try fm.contentsOfDirectory(at: Paths.runners, includingPropertiesForKeys: [.isDirectoryKey])
        return entries.compactMap { url in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return RunnerInfo(id: url.lastPathComponent, url: url)
        }.sorted { $0.id < $1.id }
    }
}
