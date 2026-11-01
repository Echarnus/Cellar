import CellarDomain
import Foundation

/// Telling the bottle's Steam client about a game Cellar downloaded itself, so the game's DLC works.
///
/// A copy DepotDownloader fetched has every file the account owns — DLC included: Steam ships most
/// DLC inside the game's own depots (Planet Coaster 2's six packs arrive with depot 2688951) and
/// DepotDownloader takes every depot the account has a licence for. But a game finds out which DLC
/// it may use by asking the running client (`ISteamApps::BIsDlcInstalled`), and the client only
/// answers yes for an app it has recorded as installed. With no appmanifest, Steam had no record of
/// the copy at all, so every DLC read as not installed and the game hid content that was on the disk.
///
/// So once a copy is downloaded, Cellar enters it in the client's library: a link at
/// `steamapps/common/<installdir>` pointing at the downloaded folder, and an
/// `appmanifest_<appid>.acf` naming the depots and manifests DepotDownloader recorded and the build
/// Steam serves. Nothing moves and nothing is downloaded again.
///
/// Updates stay Cellar's (`GameUpdates`): the entry asks Steam to update the game only when Steam
/// itself starts it, and Cellar starts this copy itself. After each Cellar update the entry is
/// written again, so Steam's record follows the files.
public enum SteamLibraryEntry {
    /// What `register` did.
    public enum Outcome: Equatable, Sendable {
        /// The entry was written (or rewritten to match the files on disk).
        case registered
        /// Already in the library exactly as it should be.
        case unchanged
        /// Nothing to do, and why: not a Steam copy Cellar downloaded, no client in the bottle,
        /// the client's own copy, or the client is running and would not read the change.
        case skipped(String)
    }

    /// Steamworks Common Redistributables (app 228980): the Visual C++, DirectX, .NET, PhysX and
    /// OpenAL depots many games pull in. Steam records them in a game's manifest as *shared*
    /// depots of that app, not as the game's own. Depot and app ids share one namespace, so no game
    /// owns these numbers.
    static let redistributablesApp: UInt32 = 228_980
    static let redistributableDepots: ClosedRange<UInt32> = 228_981...229_050

    /// Enter a downloaded copy in the bottle client's library. Safe to call on every launch: it
    /// leaves the client's own copies alone and only writes when the record would change.
    @discardableResult
    public static func register(_ plan: GamePlan,
                                clientRunning: @autoclosure () -> Bool = SteamBottle.isProcessRunning("steam.exe"),
                                now: Date = Date()) -> Outcome {
        guard plan.store == .steam, let appID = plan.appID else { return .skipped("not a Steam game") }
        guard let depots = DepotManifests.installed(in: plan.depotGameDir) else {
            return .skipped("Cellar didn't download this copy")
        }
        guard SteamBottle.isInstalled(in: plan.prefix) else { return .skipped("no Steam client in this bottle") }
        let steam = SteamBottle.steamDirectory(in: plan.prefix)
        let existing = try? String(contentsOf: manifestURL(steamDirectory: steam, appID: appID), encoding: .utf8)
        let installDir = existingInstallDir(existing) ?? plan.installDir ?? plan.name
        let library = steam.appendingPathComponent("steamapps/common/\(installDir)")
        if !isLink(library, to: plan.depotGameDir), SteamBottle.hasFiles(library) {
            return .skipped("Steam installed its own copy")
        }
        guard !clientRunning() else {
            return .skipped("Steam is running; it reads its library when it starts")
        }

        let entry = Entry(appID: appID, name: plan.name, installDir: installDir, depots: depots,
                          buildID: SteamAppInfo.buildID(appID: appID, steamDirectory: steam) ?? existingBuildID(existing),
                          sizeOnDisk: existingSizeOnDisk(existing, depots: depots) ?? UInt64(ByteSize.of(plan.depotGameDir)),
                          language: plan.language.language.steamName,
                          lastUpdated: now)
        if let existing, entry.matches(existing), isLink(library, to: plan.depotGameDir) { return .unchanged }
        do {
            try link(library, to: plan.depotGameDir)
            try entry.text.write(to: manifestURL(steamDirectory: steam, appID: appID), atomically: true, encoding: .utf8)
        } catch {
            CellarLog.warn(.install, "Couldn't add \(plan.name) to Steam's library: \(CellarLog.describe(error))",
                              subject: plan.slug)
            return .skipped("couldn't write Steam's library: \(CellarLog.describe(error))")
        }
        CellarLog.info(.install, "Added \(plan.name) to the bottle's Steam library, so its DLC is seen.",
                       subject: plan.slug)
        return .registered
    }

    /// Whether the client's entry for this game is one Cellar made: its library folder is a link to
    /// Cellar's download. Such a copy is still Cellar's to update.
    public static func isCellarEntry(_ plan: GamePlan) -> Bool {
        guard let appID = plan.appID,
              let dir = SteamBottle.installDirectory(in: plan.prefix, appID: appID) else { return false }
        let library = SteamBottle.steamDirectory(in: plan.prefix).appendingPathComponent("steamapps/common/\(dir)")
        return isLink(library, to: plan.depotGameDir)
    }

    /// The link Cellar made in the client's library, if there is one — what an uninstall removes.
    public static func libraryLink(_ plan: GamePlan) -> URL? {
        guard isCellarEntry(plan), let appID = plan.appID,
              let dir = SteamBottle.installDirectory(in: plan.prefix, appID: appID) else { return nil }
        return SteamBottle.steamDirectory(in: plan.prefix).appendingPathComponent("steamapps/common/\(dir)")
    }

    // MARK: - The manifest

    /// An `appmanifest_<appid>.acf` for a copy Cellar downloaded.
    struct Entry: Equatable {
        var appID: Int
        var name: String
        var installDir: String
        var depots: [UInt32: UInt64]
        var buildID: UInt64?
        var sizeOnDisk: UInt64
        var language: String
        var lastUpdated: Date

        var ownDepots: [(UInt32, UInt64)] {
            depots.filter { !SteamLibraryEntry.redistributableDepots.contains($0.key) }.sorted { $0.0 < $1.0 }
        }

        var sharedDepots: [UInt32] {
            depots.keys.filter { SteamLibraryEntry.redistributableDepots.contains($0) }.sorted()
        }

        var vdf: TextVDF {
            var state = TextVDF()
            state.set("appid", "\(appID)")
            state.set("universe", "1")
            state.set("name", name)
            // 4 = fully installed.
            state.set("StateFlags", "4")
            state.set("installdir", installDir)
            state.set("LastUpdated", "\(Int(lastUpdated.timeIntervalSince1970))")
            state.set("SizeOnDisk", "\(sizeOnDisk)")
            state.set("StagingSize", "0")
            state.set("buildid", "\(buildID ?? 0)")
            state.set("UpdateResult", "0")
            state.set("BytesToDownload", "0")
            state.set("BytesDownloaded", "0")
            state.set("BytesToStage", "0")
            state.set("BytesStaged", "0")
            state.set("TargetBuildID", "\(buildID ?? 0)")
            // 1 = "Only update this game when I launch it". Cellar starts this copy itself and
            // keeps it current with DepotDownloader; Steam patching the same folder behind its back
            // would leave Cellar's record of the build wrong.
            state.set("AutoUpdateBehavior", "1")
            state.set("AllowOtherDownloadsWhileRunning", "0")
            state.set("ScheduledAutoUpdate", "0")
            var installed = TextVDF()
            for (depot, manifest) in ownDepots {
                var block = TextVDF()
                block.set("manifest", "\(manifest)")
                installed.set("\(depot)", .block(block))
            }
            state.set("InstalledDepots", .block(installed))
            if !sharedDepots.isEmpty {
                var shared = TextVDF()
                for depot in sharedDepots { shared.set("\(depot)", "\(SteamLibraryEntry.redistributablesApp)") }
                state.set("SharedDepots", .block(shared))
            }
            var user = TextVDF()
            user.set("language", language)
            state.set("UserConfig", .block(user))
            state.set("MountedConfig", .block(user))
            var root = TextVDF()
            root.set("AppState", .block(state))
            return root
        }

        var text: String { vdf.text }

        /// Whether a manifest already on disk records the same copy — same folder, same depots
        /// and manifests, same build, fully installed. Timestamps and sizes don't count.
        func matches(_ text: String) -> Bool {
            guard let disk = TextVDF.parse(text)?.block("AppState") else { return false }
            guard disk.string("StateFlags") == "4", disk.string("installdir") == installDir,
                  disk.string("buildid") == "\(buildID ?? 0)" else { return false }
            guard let recorded = disk.block("InstalledDepots") else { return false }
            let recordedDepots = recorded.entries.compactMap { entry -> (String, String)? in
                guard case .block(let block) = entry.value, let manifest = block.string("manifest") else { return nil }
                return (entry.key, manifest)
            }
            let expected = ownDepots.map { ("\($0.0)", "\($0.1)") }
            return recordedDepots.count == expected.count
                && zip(recordedDepots.sorted { $0.0 < $1.0 }, expected.sorted { $0.0 < $1.0 }).allSatisfy { $0 == $1 }
        }
    }

    // MARK: - Helpers

    static func manifestURL(steamDirectory: URL, appID: Int) -> URL {
        steamDirectory.appendingPathComponent("steamapps/appmanifest_\(appID).acf")
    }

    static func existingInstallDir(_ text: String?) -> String? {
        text.flatMap { TextVDF.parse($0)?.block("AppState")?.string("installdir") }.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func existingBuildID(_ text: String?) -> UInt64? {
        text.flatMap { TextVDF.parse($0)?.block("AppState")?.string("buildid") }.flatMap { UInt64($0) }.flatMap { $0 == 0 ? nil : $0 }
    }

    /// The size an earlier entry recorded, kept so a launch doesn't walk tens of gigabytes again —
    /// unless the depots changed since, when the files did too.
    static func existingSizeOnDisk(_ text: String?, depots: [UInt32: UInt64]) -> UInt64? {
        guard let state = text.flatMap({ TextVDF.parse($0)?.block("AppState") }),
              let size = state.string("SizeOnDisk").flatMap({ UInt64($0) }), size > 0,
              let recorded = state.block("InstalledDepots") else { return nil }
        for entry in recorded.entries {
            guard case .block(let block) = entry.value, let depot = UInt32(entry.key),
                  block.string("manifest") == depots[depot].map({ "\($0)" }) else { return nil }
        }
        return size
    }

    static func isLink(_ url: URL, to target: URL) -> Bool {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { return false }
        let resolved = URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent())
        return resolved.standardizedFileURL.resolvingSymlinksInPath().path
            == target.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Point `url` at `target`, replacing a stale link or an empty folder Steam left — never a
    /// folder with files in it.
    static func link(_ url: URL, to target: URL) throws {
        let fm = FileManager.default
        if isLink(url, to: target) { return }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if Uninstall.isSymbolicLink(url) {
            try fm.removeItem(at: url)
        } else if fm.fileExists(atPath: url.path) {
            guard !SteamBottle.hasFiles(url) else {
                throw CellarError.ioFailure("\(url.path) already holds files")
            }
            try fm.removeItem(at: url)
        }
        try fm.createSymbolicLink(at: url, withDestinationURL: target)
    }
}
