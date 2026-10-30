import Foundation

/// A profile Cellar writes itself, for an owned game nobody has written one for.
///
/// Most of a player's library has no hand-made profile, so it was invisible. A draft makes it
/// playable on Cellar's best guess: the exe found in the game's files, its architecture and graphics
/// API read from the PE header (`PEImage`), and the backend that suits that API. Every guess is
/// written into the TOML where the player can read it, and a draft never claims a status other than
/// `untested` — the app shows these in their own section, saying Cellar guessed.
///
/// Drafts are ordinary user profiles (`Paths.userProfiles`) marked `generated = "true"`, so every
/// path that reads a profile works on them unchanged, and a player who gets one running can hand
/// the file in as a contributed profile.
public enum DraftProfile {

    /// An installed game with no profile: enough to write a draft from.
    public struct Candidate: Sendable, Equatable {
        public let name: String
        public let store: GameStore
        public let steamAppID: Int?
        /// The game's own directory name (`steamapps/common/<installDir>`).
        public let installDir: String
        /// Where its files are on disk now.
        public let root: URL
    }

    /// What the files say, before it is written down.
    public struct Guess: Sendable, Equatable {
        /// The exe, relative to the install directory, `/`-separated.
        public let exe: String
        public let machine: PEImage.Machine
        public let api: DetectedGraphicsAPI
    }

    /// Steam games the shared Windows Steam client has installed that no profile names. Those are
    /// the ones with files on disk to read; an owned game nobody installed has nothing to guess from.
    public static func candidates(steamLibrary: URL = Paths.sharedSteam.appendingPathComponent("steamapps", isDirectory: true),
                                  profiledAppIDs: Set<Int> = StoreLibrary.steamAppIDsInProfiles()) -> [Candidate] {
        let fm = FileManager.default
        let manifests = ((try? fm.contentsOfDirectory(at: steamLibrary, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
        var found: [Candidate] = []
        for manifest in manifests {
            guard let text = try? String(contentsOf: manifest, encoding: .utf8),
                  let appID = field("appid", in: text).flatMap(Int.init), !profiledAppIDs.contains(appID),
                  !nonGames.contains(appID),
                  let installDir = field("installdir", in: text) else { continue }
            let root = steamLibrary.appendingPathComponent("common/\(installDir)", isDirectory: true)
            guard SaveGames.isDirectory(root) else { continue }
            found.append(Candidate(name: field("name", in: text) ?? installDir, store: .steam,
                                   steamAppID: appID, installDir: installDir, root: root))
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Steam's own runtime packages, which arrive as "apps" and are not games.
    static let nonGames: Set<Int> = [228980]   // Steamworks Common Redistributables

    static func field(_ key: String, in text: String) -> String? {
        guard let match = text.range(of: "\"\(key)\"\\s*\"([^\"]*)\"", options: [.regularExpression, .caseInsensitive])
        else { return nil }
        let value = String(text[match]).components(separatedBy: "\"").dropLast().last
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Reading the files

    /// Exes that ship beside a game and are not it.
    static let notTheGame = ["unins", "setup", "install", "crash", "report", "redist", "vcredist", "vc_redist",
                             "dxsetup", "dxwebsetup", "prereq", "easyanticheat", "battleye", "beservice",
                             "updater", "helper", "touchup", "cleanup", "dotnet", "directx", "physx", "launcherpatcher"]

    /// Find the game's exe and read it. Nil when there is no exe Cellar could stand behind.
    public static func guess(root: URL, name: String) -> Guess? {
        let exes = executables(under: root)
        guard let exe = pickExe(exes.map(\.relative), name: name, sizes: Dictionary(uniqueKeysWithValues: exes.map { ($0.relative, $0.bytes) })),
              let image = PEImage.read(root.appendingPathComponent(exe)) else { return nil }
        // Engines often load the graphics API from a DLL beside the exe (UnityPlayer.dll, an Unreal
        // module), so those count as evidence too.
        var imports = image.imports
        let folder = root.appendingPathComponent(exe).deletingLastPathComponent()
        for dll in ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
        where dll.pathExtension.lowercased() == "dll" {
            imports += PEImage.read(dll)?.imports ?? []
        }
        return Guess(exe: exe, machine: image.machine, api: DetectedGraphicsAPI.detect(imports: imports))
    }

    /// Every `.exe` up to four levels down, with its size.
    static func executables(under root: URL) -> [(relative: String, bytes: Int64)] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                         options: [.skipsHiddenFiles]) else { return [] }
        var found: [(relative: String, bytes: Int64)] = []
        let base = root.standardizedFileURL.path
        for case let url as URL in walker {
            if walker.level > 4 { walker.skipDescendants(); continue }
            guard url.pathExtension.lowercased() == "exe" else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            found.append((String(path.dropFirst(base.count + 1)), Int64(size)))
        }
        return found
    }

    /// The likeliest game exe: never one of the known helpers; an Unreal `-Shipping` binary over
    /// its bootstrap; then a name that matches the game's; then the biggest.
    static func pickExe(_ paths: [String], name: String, sizes: [String: Int64]) -> String? {
        let candidates = paths.filter { path in
            let file = (path as NSString).lastPathComponent.lowercased()
            return !notTheGame.contains { file.contains($0) }
        }
        guard !candidates.isEmpty else { return nil }
        if let shipping = candidates.first(where: { $0.lowercased().hasSuffix("-shipping.exe") }) { return shipping }
        let wanted = squash(name)
        let named = candidates.filter {
            let stem = squash(((($0 as NSString).lastPathComponent) as NSString).deletingPathExtension)
            return !stem.isEmpty && (wanted.contains(stem) || stem.contains(wanted))
        }
        let pool = named.isEmpty ? candidates : named
        return pool.max { (sizes[$0] ?? 0, $1) < (sizes[$1] ?? 0, $0) }
    }

    static func squash(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Writing it down

    public static func slug(for name: String) -> String {
        let pieces = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let joined = String(pieces).split(separator: "-").joined(separator: "-")
        return joined.isEmpty ? "game" : joined
    }

    /// The draft TOML. Scalars only and no `#` inside a value, because three parsers read a
    /// profile and they disagree on everything else (skills/profiles.md).
    public static func toml(_ candidate: Candidate, guess: Guess, slug: String, runner: String = RunnerCatalog.defaultID) -> String {
        let backends = guess.api.backends
        func quoted(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "/").replacingOccurrences(of: "\"", with: "'")
                .replacingOccurrences(of: "#", with: "") + "\""
        }
        var lines = [
            "# Cellar draft profile — \(candidate.name.replacingOccurrences(of: "\n", with: " "))",
            "# Written by Cellar from the game's files, not by a person. Every value below is a guess.",
            "",
            "[game]",
            "slug          = \(quoted(slug))",
            "name          = \(quoted(candidate.name))",
            "store         = \(quoted(candidate.store.rawValue))",
        ]
        if let appID = candidate.steamAppID { lines.append("steam_appid   = \(appID)") }
        lines += [
            "graphics_api  = \(quoted(guess.api.profileValue))",
            "architecture  = \(quoted(guess.machine.rawValue))",
            "generated     = \"true\"",
            "",
            "[compatibility]",
            "status        = \"untested\"",
            "notes         = \(quoted("Cellar guessed these settings from the game's files: \(guess.exe), \(guess.machine.rawValue), \(guess.api.profileValue). Nobody has tested it yet."))",
            "",
            "[runner]",
            "id              = \(quoted(runner))",
            "windows_version = \"win10\"",
            "",
            "[graphics]",
            "backend           = \(quoted(backends.backend.rawValue))",
            "fallback_backend  = \(quoted(backends.fallback.rawValue))",
            "",
            "[install]",
            "install_dir = \(quoted(candidate.installDir))",
            "",
            "[launch]",
            "exe = \(quoted(guess.exe))",
            "",
            "[legal]",
            "drm_circumvention = \"never\"",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// Write a draft for `candidate` into the player's own profiles. Throws when the files give
    /// nothing to go on, and never overwrites a profile that already has the slug.
    @discardableResult
    public static func write(_ candidate: Candidate) throws -> String {
        guard let found = guess(root: candidate.root, name: candidate.name) else {
            throw CellarError.invalidArgument(
                "Cellar couldn't find \(candidate.name)'s Windows executable in \(candidate.installDir), so it has nothing to guess from.")
        }
        var chosen = slug(for: candidate.name)
        if ProfileStore.find(chosen) != nil { chosen += "-draft" }
        guard ProfileStore.find(chosen) == nil else {
            throw CellarError.invalidArgument("A profile called '\(chosen)' already exists. See: cellar profiles show \(chosen)")
        }
        let directory = Paths.userProfiles
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try toml(candidate, guess: found, slug: chosen)
            .write(to: directory.appendingPathComponent("\(chosen).toml"), atomically: true, encoding: .utf8)
        CellarLog.info(.app, "Wrote a draft profile for \(candidate.name): \(found.exe), \(found.api.profileValue).", subject: chosen)
        return chosen
    }
}
