import CellarDomain
import Foundation

/// Whether an installed runner is still the runner Cellar installed, and putting it right when not.
///
/// A runner is a few thousand files in the player's Library, and nothing stops one from being
/// changed: a crash halfway through an update, a cleaning tool, a test run that wrote a do-nothing
/// script over `wine` (#190). When that happens every game on the runner "starts" and nothing
/// appears, and the only way out was a Terminal command (#194). So Play checks first and repairs
/// by itself.
///
/// **What is checked.** Every install records the SHA-256 of the runner's executables — everything
/// in `wine/bin` and Wine's Unix-side loader and `ntdll.so` — in `.cellar-integrity.json` at the
/// runner's root. Before a launch those files are hashed again (a few megabytes, well under a
/// second). A runner installed before Cellar recorded this has no manifest, so it is held to the
/// one thing every runner Cellar ships has in common: `wine` and `wineserver` are real Mach-O
/// programs, not scripts or empty files. Its repair writes the manifest from then on.
///
/// **What a repair does.** The damaged runner is set aside, a fresh one is installed from the
/// pinned, checksummed downloads (`RunnerManager.install`), and the old copy is deleted. If the
/// download fails, the old copy is put back, so a repair can never leave a player with less than
/// they had. Bottles, games and saves live elsewhere and are never touched.
public enum RunnerIntegrity {
    /// The manifest's file name, at the runner's root.
    static let manifestName = ".cellar-integrity.json"

    /// What a check found.
    public enum Verdict: Equatable, Sendable {
        case intact
        /// The files that are missing, changed or not programs, relative to the runner's root.
        case damaged([String])
    }

    struct Manifest: Codable, Equatable {
        var version = 1
        /// Relative path → lowercase hex SHA-256.
        var files: [String: String]
    }

    // MARK: - Recording

    /// The files worth guarding: the executables Wine is started from, and the Unix halves every
    /// Windows process loads first. Hundreds of DLLs are left out on purpose — hashing them all on
    /// every Play would cost seconds, and a launch with a broken loader never reaches them.
    static func guardedFiles(in install: RunnerInstall) -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        if let bin = try? fm.contentsOfDirectory(at: install.binDirectory, includingPropertiesForKeys: nil) {
            files += bin.filter { isRegularFile($0) }
        }
        for lib in ["lib", "lib64"] {
            for name in ["wine", "ntdll.so"] {
                let url = install.wineRoot.appendingPathComponent("\(lib)/wine/x86_64-unix/\(name)")
                if isRegularFile(url) { files.append(url) }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    /// Write the manifest for an install that is known good — what `RunnerManager.install` calls
    /// once the files are in place.
    public static func record(_ install: RunnerInstall) throws {
        var files: [String: String] = [:]
        for file in guardedFiles(in: install) {
            files[relativePath(file, in: install.root)] = try Checksum.sha256(of: file)
        }
        let data = try JSONEncoder().encode(Manifest(files: files))
        try data.write(to: manifestURL(install.root), options: .atomic)
    }

    // MARK: - Checking

    /// Check an installed runner. Cheap enough for every Play.
    public static func check(_ install: RunnerInstall) -> Verdict {
        if let manifest = readManifest(install.root) {
            let damaged = manifest.files.keys.sorted().filter { path in
                let url = install.root.appendingPathComponent(path)
                return (try? Checksum.sha256(of: url)) != manifest.files[path]
            }
            return damaged.isEmpty ? .intact : .damaged(damaged)
        }
        // No manifest: installed before Cellar recorded one. Only what every runner shares is held.
        let required = [install.wineBinary, install.binDirectory.appendingPathComponent("wineserver")]
        let damaged = required.filter { !isMachO($0) }.map { relativePath($0, in: install.root) }
        return damaged.isEmpty ? .intact : .damaged(damaged)
    }

    /// The runner `id` names, checked — including one whose folder is there but whose `wine` is
    /// gone, which `RunnerManager.find` reports as not installed at all.
    public static func check(runnerID id: String) -> Verdict? {
        if let install = RunnerManager.find(id: id) { return check(install) }
        guard let spec = RunnerCatalog.spec(forID: id) else { return nil }
        let root = Paths.runners.appendingPathComponent(spec.id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }   // never installed
        return .damaged(["wine/bin/\(spec.wineBinaryName)"])
    }

    // MARK: - Repairing

    /// Make sure the runner `id` is intact before a launch, repairing it when it isn't.
    ///
    /// Returns whether a repair happened. Throws, saying what happened, when one was needed and
    /// could not be done; the runner is then as it was before.
    @discardableResult
    public static func ensureIntact(runnerID id: String, progress: (String) -> Void = { _ in },
                                    update: (InstallProgress) -> Void = { _ in },
                                    install: (RunnerSpec, (String) -> Void) throws -> RunnerInstall = { spec, progress in
                                        try RunnerManager.install(spec, progress: progress)
                                    }) throws -> Bool {
        guard case .damaged(let files)? = check(runnerID: id), let spec = RunnerCatalog.spec(forID: id) else {
            return false
        }
        CellarLog.warn(.runner, "\(spec.displayName) is damaged (\(files.joined(separator: ", "))); repairing it.",
                       subject: spec.id)
        let root = Paths.runners.appendingPathComponent(spec.id, isDirectory: true)
        // A Wine still running from this runner would be pulled out from under itself.
        let base = RunnerProcesses.canonicalPath(root) + "/"
        if RunnerProcesses.running().contains(where: { $0.path.hasPrefix(base) && $0.pid != getpid() }) {
            throw CellarError.ioFailure(
                "Cellar's Windows runtime needs repairing, but a game or store is still running on it. Quit it, then press Play again.")
        }
        progress("Some of the Windows runtime's files are damaged, so Cellar is installing a fresh copy. Your games and saves aren't touched.")
        update(InstallProgress(.runtimeRepair))

        let fm = FileManager.default
        try fm.createDirectory(at: Paths.cache, withIntermediateDirectories: true)
        let aside = Paths.cache.appendingPathComponent("\(spec.id)-damaged-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try fm.moveItem(at: root, to: aside)
        do {
            let fresh = try install(spec, progress)
            guard check(fresh) == .intact else {
                throw CellarError.ioFailure("the fresh copy didn't pass its own check")
            }
            try? fm.removeItem(at: aside)
            CellarLog.info(.runner, "Repaired \(spec.displayName).", subject: spec.id)
            progress("The Windows runtime is repaired.")
            return true
        } catch {
            try? fm.removeItem(at: root)
            try? fm.moveItem(at: aside, to: root)
            CellarLog.failure(.runner, "Couldn't repair \(spec.displayName)", error, subject: spec.id)
            throw CellarError.ioFailure(
                "Cellar's Windows runtime is damaged, and the fresh copy couldn't be installed (\(CellarLog.describe(error))). Check your internet connection, then press Play again to retry the repair.")
        }
    }

    // MARK: - Helpers

    static func manifestURL(_ root: URL) -> URL { root.appendingPathComponent(manifestName) }

    static func readManifest(_ root: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: manifestURL(root)),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              !manifest.files.isEmpty else { return nil }
        return manifest
    }

    static func relativePath(_ file: URL, in root: URL) -> String {
        let base = root.standardizedFileURL.path
        let path = file.standardizedFileURL.path
        return path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : path
    }

    static func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    /// Whether `url` is an executable Mach-O: thin 64-bit (either byte order) or universal.
    static func isMachO(_ url: URL) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        let magic = [UInt8](head)
        let known: [[UInt8]] = [
            [0xCF, 0xFA, 0xED, 0xFE],   // MH_MAGIC_64, little-endian on disk
            [0xFE, 0xED, 0xFA, 0xCF],   // MH_MAGIC_64, big-endian
            [0xCA, 0xFE, 0xBA, 0xBE],   // FAT_MAGIC (universal)
            [0xCA, 0xFE, 0xBA, 0xBF],   // FAT_MAGIC_64
        ]
        return known.contains(magic)
    }
}
