import CellarDomain
import Foundation

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
        let fm = FileManager.default
        let dest = Paths.runners.appendingPathComponent(spec.id, isDirectory: true)

        if let bin = locateWineBinary(in: dest, name: spec.wineBinaryName) {
            progress("\(spec.displayName) already installed.")
            return RunnerInstall(spec: spec, root: dest, wineBinary: bin)
        }
        CellarLog.info(.runner, "Installing runner \(spec.displayName) "
            + "(\(spec.artifacts.count) artifact(s) to download).", subject: spec.id)

        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for (index, artifact) in spec.artifacts.enumerated() {
            let ext = artifact.url.hasSuffix(".dmg") ? "dmg" : "tar.xz"
            let archive = Paths.cache.appendingPathComponent("\(spec.id)-\(index).\(ext)")
            if !fm.fileExists(atPath: archive.path) {
                progress("Downloading \(artifact.url)")
                CellarLog.debug(.runner, "Downloading \(artifact.url)", subject: spec.id)
                try Downloader.fetch(artifact.url, to: archive)
            } else {
                progress("Using cached \(archive.lastPathComponent)")
            }
            // Fresh or cached, nothing is unpacked until it is the exact file this build pinned.
            try Checksum.verify(archive, sha256: artifact.sha256, what: artifact.url)

            if artifact.kind == .wineDMG {
                progress("Copying Wine out of \(archive.lastPathComponent)…")
                let target = dest.appendingPathComponent("wine", isDirectory: true)
                try? fm.removeItem(at: target)
                try Archive.withMountedDMG(archive) { mount in
                    try fm.copyItem(at: mount.appendingPathComponent(artifact.payloadPath), to: target)
                }
                try? fm.removeItem(at: archive)
                continue
            }

            let staging = Paths.cache.appendingPathComponent("\(spec.id)-\(index)-extract", isDirectory: true)
            try? fm.removeItem(at: staging)
            progress("Extracting \(archive.lastPathComponent)…")
            try Archive.extractTar(archive, to: staging)

            switch artifact.kind {
            case .wineDMG:
                break // handled above
            case .d3dmetalFromTemplate:
                let payload = staging.appendingPathComponent(artifact.payloadPath)
                let target = dest.appendingPathComponent("wine/lib/d3dmetal", isDirectory: true)
                try? fm.removeItem(at: target)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: payload, to: target)
            case .wineEngine:
                let payload = staging.appendingPathComponent(artifact.payloadPath)
                let target = dest.appendingPathComponent("wine", isDirectory: true)
                try? fm.removeItem(at: target)
                try fm.moveItem(at: payload, to: target)
            case .wrapperFrameworks:
                let payload = staging.appendingPathComponent(artifact.payloadPath)
                let target = dest.appendingPathComponent("Frameworks", isDirectory: true)
                try? fm.removeItem(at: target)
                try fm.moveItem(at: payload, to: target)
            case .gptkApp:
                // The archive already is the runner layout (`<name>.app/Contents/Resources/wine`).
                for item in try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
                    try fm.moveItem(at: item, to: dest.appendingPathComponent(item.lastPathComponent))
                }
            }
            try? fm.removeItem(at: staging)
            try? fm.removeItem(at: archive)
        }

        guard let bin = locateWineBinary(in: dest, name: spec.wineBinaryName) else {
            throw CellarError.ioFailure(
                "Could not find '\(spec.wineBinaryName)' after installing \(spec.displayName).")
        }
        return RunnerInstall(spec: spec, root: dest, wineBinary: bin)
    }

    // MARK: - Internals

    /// Find `.../bin/<name>` inside a runner root. Engine runners keep it at `wine/bin/<name>`;
    /// GPTK keeps it at `<app>/Contents/Resources/wine/bin/<name>`.
    static func locateWineBinary(in root: URL, name: String) -> URL? {
        let direct = root.appendingPathComponent("wine/bin/\(name)")
        if FileManager.default.isExecutableFile(atPath: direct.path) { return direct }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator {
            if url.lastPathComponent == name, url.deletingLastPathComponent().lastPathComponent == "bin",
               url.path.contains("/wine/bin/"),
               // Same demand as the direct path above. Without it a half-extracted download, or one
               // whose permissions were stripped, reports as an installed runner and then fails at
               // exec time with something nobody can read — rather than honestly saying it is not
               // installed yet.
               FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
