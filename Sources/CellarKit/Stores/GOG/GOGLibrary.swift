import CellarDomain
import Foundation

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

        // The language every game uses (the Mac's, unless the player picked another), not
        // `Locale.current` — that is the region's, and an English Mac in Belgium would get Dutch.
        let preferred = String(LanguageChoice.global().language.code.prefix(2))
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
