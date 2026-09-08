import Foundation

/// Each store's **own** icon, taken from the copy of that store already on this machine.
///
/// A drawn approximation of the Steam valve is recognisable; Valve's actual artwork is
/// unmistakable, and telling the stores apart at a glance is the whole reason a mark exists
/// (`skills/ux.md`). So where Cellar can lay hands on the real thing, it uses the real thing.
///
/// It never *ships* the real thing. Every storefront's brand guidelines say the same, in different
/// words — Valve's forbid the Steam logo as a prominent feature on non-Valve materials and reserve
/// approval of anything that carries it; Blizzard's permit their marks only for the fan-site,
/// tournament and custom-map activities they list, and only non-commercially; GOG publishes a press
/// kit but grants nobody a licence in it. On top of that Cellar is GPL-3.0, and a logo file in
/// `Resources/` would be artwork we are relicensing without the right to. See `docs/LEGAL.md`.
///
/// The way out is the one Cellar already uses for Apple's D3DMetal: **graft, don't bundle.** The
/// player installed Steam; that install contains Valve's own icon; Cellar points at it. Nothing
/// enters the repository or the disk image, and the artwork on screen is authentic rather than
/// approximated. When a store isn't installed there is nothing to point at, and the app falls back
/// to the vector mark it draws itself (`StoreMark`) — which is why that fallback still has to be
/// good, not a placeholder.
public enum StoreIcon {

    // MARK: - Sources

    /// The store's icon as macOS itself has it: the `.icns` inside the store's native Mac app.
    ///
    /// Kept separate from `mark` because a generated `.app` bundle can only take an `.icns` for
    /// `CFBundleIconFile` — a PNG there silently produces a blank icon.
    public static func nativeICNS(_ store: GameStore) -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let roots = ["/Applications", "\(home)/Applications"]

        // Names differ in case between versions, and a case-sensitive volume cares.
        let candidates: [String]
        switch store {
        case .steam:
            candidates = ["Steam.app/Contents/Resources/Steam.icns"]
        case .battlenet:
            candidates = ["Battle.net.app/Contents/Resources/battle.net.icns",
                          "Battle.net.app/Contents/Resources/Battle.net.icns"]
        case .gog:
            // Galaxy's icon file has been renamed across versions, so find it rather than name it.
            candidates = []
        case .standalone:
            return nil
        }

        if let hit = roots.flatMap({ root in candidates.map { URL(fileURLWithPath: "\(root)/\($0)") } })
            .first(where: { fm.fileExists(atPath: $0.path) }) {
            return hit
        }

        if store == .gog {
            return roots.map { URL(fileURLWithPath: "\($0)/GOG Galaxy.app") }
                .compactMap(declaredIcon(ofApp:))
                .first
        }
        return nil
    }

    /// The `.icns` a Mac app's own `Info.plist` names in `CFBundleIconFile` — the app icon itself,
    /// rather than whichever `.icns` in `Resources/` happens to be biggest (which is as likely to be
    /// a document icon). The key is conventionally written without its extension.
    private static func declaredIcon(ofApp app: URL) -> URL? {
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let name = (plist as? [String: Any])?["CFBundleIconFile"] as? String
        else { return nil }
        let icns = resources.appendingPathComponent(
            name.hasSuffix(".icns") ? name : "\(name).icns")
        return FileManager.default.fileExists(atPath: icns.path) ? icns : nil
    }

    /// The store's icon as its **Windows** client has it, inside a bottle Cellar set up.
    ///
    /// This is the common case: a player who is using Cellar for Steam has Windows Steam installed
    /// by Cellar whether or not they ever installed the Mac client. Windows Steam keeps its logo as
    /// a loose `.ico` in `public/`; Battle.net has no such well-known file, so its install
    /// directory is searched and may legitimately come up empty.
    static func bottleICO(_ store: GameStore) -> URL? {
        let fm = FileManager.default
        switch store {
        case .steam:
            // The tray icon is the full-colour Steam mark at 256px — the same artwork as the app
            // icon, and the only one Valve ships as a plain file.
            let names = ["public/steam_tray.ico", "public/steam_offline.ico"]
            var roots = [Paths.sharedSteam]
            roots += bottleDirectories().map {
                $0.appendingPathComponent("drive_c/Program Files (x86)/Steam")
            }
            return roots.flatMap { root in names.map { root.appendingPathComponent($0) } }
                .first { fm.fileExists(atPath: $0.path) }

        case .battlenet:
            return bottleDirectories()
                .map { $0.appendingPathComponent(BattleNetBottle.relativeInstallPath) }
                .compactMap { largestFile(in: $0, extension: "ico") }
                .first

        // GOG is pure HTTP — Cellar never stands a Galaxy client up in a bottle, so there is no
        // Windows install to take an icon from. Standalone games have no client at all.
        case .gog, .standalone:
            return nil
        }
    }

    // MARK: - Resolution

    /// A file the UI can draw as this store's mark, or nil when the store isn't installed anywhere
    /// Cellar can see. Native artwork wins over the Windows client's: it is the icon the player
    /// already associates with the store on this machine.
    ///
    /// A Windows `.ico` is converted to a PNG once and cached under `Paths.cache/store-icons/`;
    /// the cache is rebuilt whenever the source is newer, so a Steam update refreshes the mark.
    public static func mark(_ store: GameStore) -> URL? {
        if let icns = nativeICNS(store) { return icns }
        guard let ico = bottleICO(store) else { return nil }

        let fm = FileManager.default
        let cached = Paths.cache
            .appendingPathComponent("store-icons", isDirectory: true)
            .appendingPathComponent("\(store.rawValue).png")
        if isFresh(cached, comparedTo: ico) { return cached }

        try? fm.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: cached)
        // 256px is what the source holds and what a Retina badge on a 92pt cover asks for.
        guard Shell.run("/usr/bin/sips",
                        ["-s", "format", "png", "-Z", "256", ico.path, "--out", cached.path]).succeeded,
              fm.fileExists(atPath: cached.path) else { return nil }
        return cached
    }

    // MARK: - Helpers

    /// Every bottle Cellar has made, so a store client can be found in whichever one installed it.
    private static func bottleDirectories() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: Paths.prefixes, includingPropertiesForKeys: nil)) ?? []
    }

    /// The biggest file of a given extension directly inside a directory — a decent proxy for "the
    /// real logo" among an app's assorted UI chrome.
    private static func largestFile(in directory: URL, extension ext: String) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        return entries
            .filter { $0.pathExtension.lowercased() == ext }
            .max { a, b in size(of: a) < size(of: b) }
    }

    private static func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private static func isFresh(_ cached: URL, comparedTo source: URL) -> Bool {
        guard let cachedDate = modified(cached), let sourceDate = modified(source) else { return false }
        return cachedDate >= sourceDate
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
