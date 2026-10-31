import CellarDomain
import Foundation

/// Downloads an owned GOG game and installs it into a bottle.
///
/// GOG ships plain Windows installers (Inno Setup), so this is the whole story: fetch the parts,
/// run the setup silently into `C:\Games\<slug>`, and the profile's `exe` is then launchable
/// directly — no store client in the bottle, nothing running alongside the game.
public enum GOGInstall {
    /// Download the installer parts into the cache, resuming anything already there.
    public static func download(productID: Int, progress: (String) -> Void) throws -> [URL] {
        let files = try GOGLibrary.windowsInstallerFiles(productID: productID)
        let total = files.reduce(Int64(0)) { $0 + $1.sizeBytes }
        progress("Downloading \(files.count) file\(files.count == 1 ? "" : "s") (\(humanSize(total))) from GOG…")

        let directory = Paths.cache.appendingPathComponent("gog/\(productID)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var downloaded: [URL] = []
        for (index, file) in files.enumerated() {
            let destination = directory.appendingPathComponent(file.name)
            if isComplete(destination, expecting: file.sizeBytes) {
                progress("\(index + 1)/\(files.count) \(file.name) — already downloaded.")
                downloaded.append(destination)
                continue
            }
            progress("\(index + 1)/\(files.count) \(file.name) (\(humanSize(file.sizeBytes)))…")
            let url = try GOGLibrary.resolveDownlink(file)
            try Downloader.fetch(url, to: destination, bearer: try GOGAuth.accessToken())
            downloaded.append(destination)
        }
        guard let setup = downloaded.first, WindowsInstaller.isPortableExecutable(setup) else {
            throw CellarError.ioFailure(
                "The file GOG sent isn't a Windows installer. Delete \(directory.path) and try again.")
        }
        return downloaded
    }

    /// Run the downloaded installer inside the bottle, silently, into `C:\Games\<slug>`.
    ///
    /// GOG's installers are Inno Setup, which documents these switches; `/VERYSILENT` means no
    /// window at all, so the caller must say a long pause is expected before calling this.
    public static func install(setup: URL, slug: String, runner: WineRunner,
                               progress: (String) -> Void) throws {
        let target = "C:\\Games\\\(slug)"
        progress("Installing into \(target) — this takes a few minutes with no window to watch.")
        runner.runExecutable(setup.path,
                             args: ["/VERYSILENT", "/NORESTART", "/SP-", "/SUPPRESSMSGBOXES",
                                    "/NOICONS", "/DIR=\(target)"],
                             inheritIO: true)
        runner.waitForServer()
    }

    static func isComplete(_ file: URL, expecting size: Int64) -> Bool {
        guard size > 0,
              let onDisk = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64
        else { return false }
        return onDisk == size
    }

    /// "~1.4 GB" — sizes are human, per skills/ux.md.
    public static func humanSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "unknown size" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = bytes > 1_000_000_000 ? [.useGB] : [.useMB]
        return formatter.string(fromByteCount: bytes)
    }
}
