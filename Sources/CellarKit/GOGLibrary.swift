import Foundation

/// One owned GOG game, as much of it as Cellar needs to show a row and install it.
public struct GOGProduct: Sendable, Identifiable {
    public let id: Int
    public let title: String
    public let slug: String
    /// Portrait / landscape art GOG publishes for the product, if any.
    public let portraitURL: String?
    public let heroURL: String?
    /// Whether GOG offers a Windows installer for it — a Linux-or-Mac-only title can't run here, and
    /// saying so up front beats a download that ends in "no exe found".
    public let hasWindowsInstaller: Bool
}

/// One downloadable installer file (GOG splits large games into a setup .exe plus .bin parts).
public struct GOGInstallerFile: Sendable {
    public let name: String
    public let sizeBytes: Int64
    /// The token-gated indirection URL; resolve it to a real content URL right before downloading.
    public let downlinkURL: String
}

/// Reads the signed-in player's GOG library.
public enum GOGLibrary {
    /// Product ids the player owns. One call, and it is the whole library — which is what makes a
    /// "browse everything you own" screen possible for GOG and not for the other two stores.
    public static func ownedProductIDs() throws -> [Int] {
        let data = try Downloader.json("\(GOG.embedHost)/user/data/games", bearer: try GOGAuth.accessToken())
        guard let owned = data["owned"] as? [Int] else {
            throw CellarError.ioFailure("GOG did not return your owned games.")
        }
        return owned
    }

    /// Full detail for one product.
    public static func product(id: Int) throws -> GOGProduct {
        let data = try Downloader.json("\(GOG.apiHost)/products/\(id)?expand=downloads",
                                       bearer: try GOGAuth.accessToken())
        let title = (data["title"] as? String) ?? "GOG product \(id)"
        let slug = (data["slug"] as? String) ?? "gog-\(id)"
        let images = data["images"] as? [String: Any]
        return GOGProduct(
            id: id,
            title: title,
            slug: slug,
            portraitURL: normalized(images?["logo"] as? String),
            heroURL: normalized(images?["background"] as? String),
            hasWindowsInstaller: !installerFiles(in: data).isEmpty)
    }

    /// The Windows installer files for a product, in download order.
    public static func windowsInstallerFiles(productID: Int) throws -> [GOGInstallerFile] {
        let data = try Downloader.json("\(GOG.apiHost)/products/\(productID)?expand=downloads",
                                       bearer: try GOGAuth.accessToken())
        let files = installerFiles(in: data)
        guard !files.isEmpty else {
            throw CellarError.invalidArgument(
                "GOG has no Windows installer for product \(productID) — Cellar can only run Windows builds.")
        }
        return files
    }

    /// Turn GOG's token-gated indirection URL into the real content URL. Resolved immediately before
    /// each download because it is short-lived.
    public static func resolveDownlink(_ file: GOGInstallerFile) throws -> String {
        let data = try Downloader.json(file.downlinkURL, bearer: try GOGAuth.accessToken())
        guard let url = data["downlink"] as? String else {
            throw CellarError.ioFailure("GOG did not return a download link for \(file.name).")
        }
        return url
    }

    // MARK: - Parsing

    /// Pick the English Windows installer out of `downloads.installers`, preferring the player's own
    /// language when GOG offers it.
    static func installerFiles(in product: [String: Any]) -> [GOGInstallerFile] {
        guard let downloads = product["downloads"] as? [String: Any],
              let installers = downloads["installers"] as? [[String: Any]] else { return [] }
        let windows = installers.filter { ($0["os"] as? String) == "windows" }
        guard !windows.isEmpty else { return [] }

        let preferred = Locale.current.language.languageCode?.identifier ?? "en"
        let chosen = windows.first { ($0["language"] as? String)?.hasPrefix(preferred) == true }
            ?? windows.first { ($0["language"] as? String)?.hasPrefix("en") == true }
            ?? windows[0]

        guard let files = chosen["files"] as? [[String: Any]] else { return [] }
        return files.enumerated().compactMap { index, file in
            guard let downlink = file["downlink"] as? String else { return nil }
            let size = (file["size"] as? Int64) ?? Int64((file["size"] as? Int) ?? 0)
            // GOG doesn't always name the parts; a stable synthetic name keeps resumes working.
            let name = (file["id"] as? String).map { "\($0).exe" }
                ?? "gog-installer-part\(index + 1)\(index == 0 ? ".exe" : ".bin")"
            return GOGInstallerFile(name: name, sizeBytes: size, downlinkURL: downlink)
        }
    }

    /// GOG returns protocol-relative image URLs (`//images.gog.com/…`).
    static func normalized(_ url: String?) -> String? {
        guard let url, !url.isEmpty else { return nil }
        if url.hasPrefix("//") { return "https:" + url }
        return url
    }
}

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
