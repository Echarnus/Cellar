import Foundation

/// Describes a downloadable Wine runner family (where to get it, how it's laid out).
public struct RunnerSpec {
    public let id: String            // Cellar id, e.g. "gptk"
    public let displayName: String
    public let githubRepo: String    // "Gcenx/game-porting-toolkit"
    public let assetPrefix: String   // filter assets[].name by prefix
    public let assetSuffix: String   // and suffix
    public let wineBinaryName: String // "wine" (Wine 11 wow64) or "wine64" (GPTK)
    public let hasD3DMetal: Bool
    public let license: String
    public let pinnedURL: String?    // fallback if the GitHub API can't be reached
}

/// The runners Cellar knows how to install.
public enum RunnerCatalog {
    /// Apple's D3DMetal path (DX11/12 → Metal). Required for modern DX12 games like Planet Coaster 2.
    /// Redistributed by Gcenx under Apple's non-commercial-distribution grant; fetched at runtime,
    /// never bundled in Cellar's own artifacts.
    public static let gptk = RunnerSpec(
        id: "gptk",
        displayName: "Game Porting Toolkit (Wine 7.7 + Apple D3DMetal)",
        githubRepo: "Gcenx/game-porting-toolkit",
        assetPrefix: "game-porting-toolkit",
        assetSuffix: ".tar.xz",
        wineBinaryName: "wine64",
        hasD3DMetal: true,
        license: "Wine: LGPL-2.1+ · D3DMetal: Apple proprietary (non-commercial)",
        pinnedURL: "https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz"
    )

    /// Fully open Wine 11 (single-binary wow64). No D3DMetal — pairs with DXVK/DXMT for DX9/older.
    public static let wineStaging = RunnerSpec(
        id: "wine-staging",
        displayName: "Wine Staging 11 (LGPL, no D3DMetal)",
        githubRepo: "Gcenx/macOS_Wine_builds",
        assetPrefix: "wine-staging",
        assetSuffix: "-osx64.tar.xz",
        wineBinaryName: "wine",
        hasD3DMetal: false,
        license: "LGPL-2.1+",
        pinnedURL: nil
    )

    public static let all = [gptk, wineStaging]
    public static func spec(forID id: String) -> RunnerSpec? { all.first { $0.id == id } }
}

/// A runner installed on disk, with its resolved wine binary.
public struct RunnerInstall {
    public let spec: RunnerSpec
    public let root: URL
    public let wineBinary: URL
    public var binDirectory: URL { wineBinary.deletingLastPathComponent() }
}

public enum RunnerManager {
    /// List installed runners (those Cellar recognises and whose wine binary is present).
    public static func installed() -> [RunnerInstall] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: Paths.runners, includingPropertiesForKeys: nil) else { return [] }
        return entries.compactMap { dir in
            guard let spec = RunnerCatalog.spec(forID: dir.lastPathComponent),
                  let bin = locateWineBinary(in: dir, name: spec.wineBinaryName) else { return nil }
            return RunnerInstall(spec: spec, root: dir, wineBinary: bin)
        }.sorted { $0.spec.id < $1.spec.id }
    }

    public static func find(id: String) -> RunnerInstall? {
        installed().first { $0.spec.id == id }
    }

    /// Install a runner (idempotent — returns the existing install if already present).
    @discardableResult
    public static func install(_ spec: RunnerSpec, progress: (String) -> Void = { _ in }) throws -> RunnerInstall {
        try Paths.ensureBaseDirectories()
        let dest = Paths.runners.appendingPathComponent(spec.id, isDirectory: true)

        if let bin = locateWineBinary(in: dest, name: spec.wineBinaryName) {
            progress("\(spec.displayName) already installed.")
            return RunnerInstall(spec: spec, root: dest, wineBinary: bin)
        }

        progress("Resolving latest \(spec.displayName)…")
        let url = try resolveDownloadURL(spec)

        let archive = Paths.cache.appendingPathComponent("\(spec.id).tar.xz")
        progress("Downloading \(url)")
        try Downloader.fetch(url, to: archive)

        progress("Extracting (this unpacks a few hundred MB)…")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Archive.extractTar(archive, to: dest)
        try? FileManager.default.removeItem(at: archive)

        guard let bin = locateWineBinary(in: dest, name: spec.wineBinaryName) else {
            throw CellarError.ioFailure(
                "Could not find '\(spec.wineBinaryName)' after extracting \(spec.displayName).")
        }
        return RunnerInstall(spec: spec, root: dest, wineBinary: bin)
    }

    // MARK: - Internals

    static func resolveDownloadURL(_ spec: RunnerSpec) throws -> String {
        let api = "https://api.github.com/repos/\(spec.githubRepo)/releases/latest"
        if let json = try? Downloader.string(api),
           let url = parseAssetURL(json, prefix: spec.assetPrefix, suffix: spec.assetSuffix) {
            return url
        }
        if let pinned = spec.pinnedURL { return pinned }
        throw CellarError.ioFailure("Could not resolve a download URL for \(spec.displayName).")
    }

    static func parseAssetURL(_ json: String, prefix: String, suffix: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let release: [String: Any]?
        if let arr = obj as? [[String: Any]] { release = arr.first }
        else { release = obj as? [String: Any] }
        guard let assets = release?["assets"] as? [[String: Any]] else { return nil }
        for asset in assets {
            if let name = asset["name"] as? String,
               name.hasPrefix(prefix), name.hasSuffix(suffix),
               let url = asset["browser_download_url"] as? String {
                return url
            }
        }
        return nil
    }

    /// Find `Contents/Resources/wine/bin/<name>` inside an extracted runner (the .app name varies).
    static func locateWineBinary(in root: URL, name: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator {
            if url.lastPathComponent == name, url.path.contains("/Contents/Resources/wine/bin/") {
                return url
            }
        }
        return nil
    }
}
