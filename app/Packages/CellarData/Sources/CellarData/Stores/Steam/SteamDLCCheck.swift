import CellarDomain
import Foundation

/// `cellar verify`'s `dlc` check: Steam knows the game is installed, so the game sees its DLC (#208).
///
/// A game asks the running client which DLC it may use (`ISteamApps::BIsDlcInstalled`), and the
/// client only answers yes for an app it has recorded as fully installed. A copy Steam has no record
/// of reads every DLC as missing, even with the files on disk (#185). So the check is what Steam
/// itself would answer: an `appmanifest_<appid>.acf` saying fully installed (`StateFlags 4`) and,
/// for a copy Cellar downloaded, listing every depot that came down, DLC depots included. That is
/// also how most DLC arrives: inside the game's own depots (Planet Coaster 2's six packs come with
/// depot 2688951).
public enum SteamDLCCheck {
    static let title = "Steam records the game as installed with every depot, so its DLC is seen"

    /// - `manifest`: the bottle's `appmanifest_<appid>.acf`, if there is one.
    /// - `downloadedDepots`: the depots DepotDownloader recorded for a copy Cellar downloaded, or
    ///   nil for a copy the Steam client installed itself.
    static func check(manifest: String?, downloadedDepots: [UInt32: UInt64]?) -> VerificationCheck {
        func check(_ verdict: VerificationVerdict, _ detail: String, _ evidence: [String] = []) -> VerificationCheck {
            VerificationCheck(id: "dlc", title: title, verdict: verdict, detail: detail, evidence: evidence)
        }
        guard let manifest, let vdf = TextVDF.parse(manifest), let state = vdf.block("AppState") else {
            return check(.fail, "The bottle's Steam has no record of this game (no appmanifest), so every DLC reads as not installed.")
        }
        guard state.string("StateFlags") == "4" else {
            return check(.fail, "Steam doesn't record the game as fully installed (StateFlags \(state.string("StateFlags") ?? "missing")), so it won't report its DLC as installed.")
        }
        let listed = Set((state.block("InstalledDepots")?.entries ?? []).compactMap { UInt32($0.key) })
        guard let downloadedDepots else {
            return check(.pass, "Steam installed this copy itself and records it as fully installed with \(listed.count) depot\(listed.count == 1 ? "" : "s"); it manages the DLC.")
        }
        let own = Set(downloadedDepots.keys).subtracting(SteamLibraryEntry.redistributableDepots)
        let missing = own.subtracting(listed).sorted()
        if !missing.isEmpty {
            return check(.fail, "\(missing.count) depot\(missing.count == 1 ? "" : "s") Cellar downloaded \(missing.count == 1 ? "isn't" : "aren't") in Steam's record, so the DLC in \(missing.count == 1 ? "it" : "them") reads as not installed.",
                         missing.map { "depot \($0) downloaded, not in appmanifest" })
        }
        return check(.pass, "Steam records the game as fully installed with all \(own.count) depot\(own.count == 1 ? "" : "s") Cellar downloaded, DLC included.")
    }

    /// The check, read from the bottle as it is now.
    public static func check(_ plan: GamePlan) -> VerificationCheck {
        guard let appID = plan.appID else {
            return VerificationCheck(id: "dlc", title: title, verdict: .couldNotCheck,
                                     detail: "The profile names no Steam AppID.")
        }
        guard SteamBottle.isInstalled(in: plan.prefix) else {
            return VerificationCheck(id: "dlc", title: title, verdict: .couldNotCheck,
                                     detail: "This bottle has no Steam client, so no Steam answers the game's DLC questions; the game reads its DLC from its own files.")
        }
        let manifest = try? String(contentsOf: SteamBottle.steamDirectory(in: plan.prefix)
            .appendingPathComponent("steamapps/appmanifest_\(appID).acf"), encoding: .utf8)
        return check(manifest: manifest, downloadedDepots: DepotManifests.installed(in: plan.depotGameDir))
    }
}
