import CellarDomain
import Darwin
import Foundation

/// A second Cellar installation that can never change the player's real one (#204).
///
/// Tests and `cellar verify` both stand up a throwaway Cellar home and point `CELLAR_HOME` at it.
/// That only protects the player if nothing inside the throwaway home can reach back out. #190 is
/// what happens otherwise: the test home *linked* the real WineForge runner, a fake Wine was
/// written through the link, and every Play after that started nothing.
///
/// So the rules are:
/// - **A sandbox is never the real home, inside it, or around it** (`requireSeparate`).
/// - **What a sandbox borrows from the real home is cloned, never linked** (`clone`). On APFS a
///   clone costs no disk space and no time, and a write to it lands in the clone alone. A link
///   inside the borrowed tree that points back into the real home is replaced by a clone of what
///   it points at, so no path through the copy leads home.
/// - **The real runners are fingerprinted before and after a run** (`Fingerprint`), so a write
///   that slips past both rules anyway is caught and named rather than found by a player.
public enum CellarSandbox {
    /// The player's real installation: where `Paths.appSupport` points when `CELLAR_HOME` is unset.
    public static var realHome: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cellar", isDirectory: true)
    }

    // MARK: - Where a path really is

    /// Where `url` really is: every link on the way followed, including those in folders above a
    /// file that does not exist yet (which `resolvingSymlinksInPath` leaves alone, and which is
    /// exactly the case of a file about to be written through a linked folder).
    public static func canonicalPath(_ url: URL) -> String {
        let fm = FileManager.default
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while existing.path != "/", !fm.fileExists(atPath: existing.path) {
            rest.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        var base = existing.path
        if let pointer = realpath(existing.path, nil) {
            base = String(cString: pointer)
            free(pointer)
        }
        if base == "/" { return rest.isEmpty ? "/" : "/" + rest.joined(separator: "/") }
        return ([base] + rest).joined(separator: "/")
    }

    /// Whether `inner` is `outer` or somewhere below it. Both are canonical paths.
    static func path(_ inner: String, isWithin outer: String) -> Bool {
        if outer == "/" { return true }
        return inner == outer || inner.hasPrefix(outer + "/")
    }

    /// Whether writing at `url` could change the real installation: it is the real home, inside
    /// it, or a folder the real home sits inside.
    public static func overlapsRealHome(_ url: URL, realHome: URL = realHome) -> Bool {
        let path = canonicalPath(url)
        let real = canonicalPath(realHome)
        return Self.path(path, isWithin: real) || Self.path(real, isWithin: path)
    }

    /// Refuse a sandbox home that is, contains, or sits inside the real installation.
    public static func requireSeparate(_ home: URL, realHome: URL = realHome) throws {
        guard !overlapsRealHome(home, realHome: realHome) else {
            throw CellarError.invalidArgument(
                "Cellar won't use \(home.path) as a sandbox, because it overlaps the real Cellar installation at \(realHome.path). A test or verification run must never write there.")
        }
    }

    // MARK: - Borrowing from the real installation

    /// Copy `source` to `destination` as an APFS clone, falling back to an ordinary copy on a
    /// volume that can't clone. Never a link.
    ///
    /// `destination` must not exist yet and must lie outside the real installation. After the
    /// copy, any link inside it that leads back into the real installation is replaced by a clone
    /// of what it points at.
    public static func clone(_ source: URL, to destination: URL, realHome: URL = realHome) throws {
        guard !overlapsRealHome(destination, realHome: realHome) else {
            throw CellarError.invalidArgument(
                "Cellar won't copy into \(destination.path), because it is inside the real Cellar installation.")
        }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else {
            throw CellarError.ioFailure("Cellar can't copy into \(destination.path): something is already there.")
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if clonefile(source.path, destination.path, 0) != 0 {
            let reason = errno
            // Not APFS, or another volume: an ordinary copy is just as separate, only slower.
            guard reason == ENOTSUP || reason == EXDEV else {
                throw CellarError.ioFailure(
                    "Cellar couldn't copy \(source.lastPathComponent) into its sandbox (\(String(cString: strerror(reason)))).")
            }
            try fm.copyItem(at: source, to: destination)
        }
        try detachLinks(in: destination, realHome: realHome)
    }

    /// Replace every link under `root` that leads into the real installation with a copy of its
    /// target, so writing through the sandbox can never reach the real files. Links that stay
    /// inside the copy (the usual `libfoo.dylib -> libfoo.1.dylib`) are left alone.
    static func detachLinks(in root: URL, realHome: URL) throws {
        let fm = FileManager.default
        var links: [URL] = []
        if isSymbolicLink(root) { links.append(root) }
        if let walk = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let url as URL in walk where isSymbolicLink(url) { links.append(url) }
        }
        let real = canonicalPath(realHome)
        // Only a link *into* the real home is copied. One that points above it (at ~/Library,
        // say) is just removed: copying that would copy far more than Cellar's own files.
        for link in links where overlapsRealHome(link, realHome: realHome) {
            let target = URL(fileURLWithPath: canonicalPath(link))
            guard path(target.path, isWithin: real) else {
                try fm.removeItem(at: link)
                continue
            }
            try fm.removeItem(at: link)
            if fm.fileExists(atPath: target.path) {
                if clonefile(target.path, link.path, 0) != 0 { try fm.copyItem(at: target, to: link) }
                try detachLinks(in: link, realHome: realHome)
            }
        }
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    // MARK: - Proving nothing changed

    /// The SHA-256 of every file a runner is started from, across a folder of runners.
    ///
    /// The same files `RunnerIntegrity` guards — everything in a `bin` folder, and Wine's Unix-side
    /// `wine` loader and `ntdll.so` — found by walking each runner, so it works on any folder of
    /// runners (the real one included) without asking `Paths` where runners live.
    public struct Fingerprint: Equatable, Sendable {
        /// `<runner>/<path inside it>` → lowercase hex SHA-256.
        public let files: [String: String]

        public init(files: [String: String]) { self.files = files }

        /// Fingerprint every runner under `runners`. A folder that isn't there has no files.
        public static func of(runnersAt runners: URL) -> Fingerprint {
            let fm = FileManager.default
            let base = runners.standardizedFileURL.path
            var files: [String: String] = [:]
            guard let walk = fm.enumerator(at: runners, includingPropertiesForKeys: [.isRegularFileKey]) else {
                return Fingerprint(files: [:])
            }
            for case let url as URL in walk {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                      isGuarded(url) else { continue }
                let path = url.standardizedFileURL.path
                let relative = path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : path
                files[relative] = (try? Checksum.sha256(of: url)) ?? "unreadable"
            }
            return Fingerprint(files: files)
        }

        static func isGuarded(_ url: URL) -> Bool {
            let folder = url.deletingLastPathComponent().lastPathComponent
            if folder == "bin" { return true }
            return folder == "x86_64-unix" && ["wine", "ntdll.so"].contains(url.lastPathComponent)
        }

        /// What differs from `earlier`, one sentence per file, sorted: changed, added or removed.
        public func changes(since earlier: Fingerprint) -> [String] {
            var changes: [String] = []
            for path in Set(files.keys).union(earlier.files.keys).sorted() {
                switch (earlier.files[path], files[path]) {
                case (nil, _?): changes.append("\(path) was added")
                case (_?, nil): changes.append("\(path) was removed")
                case (let before?, let after?) where before != after: changes.append("\(path) was changed")
                default: break
                }
            }
            return changes
        }
    }
}
