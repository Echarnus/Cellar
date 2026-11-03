import CellarDomain
import Foundation

/// The signed-in Steam account's own picture, for the account button at the foot of the sidebar.
///
/// Read from the player's public Steam Community profile (`/profiles/<SteamID>/?xml=1`), which needs
/// no key and no sign-in, and kept as one file in Cellar's shared folder. Nothing secret is sent or
/// kept: the SteamID is the public number in the profile's address, and the picture is public.
/// Re-fetched once a week, so a changed picture catches up without asking Steam on every launch.
/// Any failure (offline, a private profile, a host Cellar doesn't expect) leaves the generic person
/// in place; it is a nicety, never a step a player waits on.
public enum SteamAvatar {
    /// How long a fetched picture is used before asking again.
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    /// Where `account`'s picture is kept: one file per account, so a different sign-in never shows
    /// the last person's face beside its own name.
    static func file(for account: String, in shared: URL = Paths.shared) -> URL {
        let safe = account.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
        return shared.appendingPathComponent("steam-avatar-\(safe.isEmpty ? "account" : safe).jpg")
    }

    /// `account`'s picture, when Cellar has one.
    public static func localFile(for account: String?, in shared: URL = Paths.shared) -> URL? {
        guard let account else { return nil }
        let url = file(for: account, in: shared)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Whether `account`'s picture is missing or old enough to fetch again.
    public static func isStale(for account: String, in shared: URL = Paths.shared, now: Date = Date()) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file(for: account, in: shared).path),
              let modified = attributes[.modificationDate] as? Date else { return true }
        return now.timeIntervalSince(modified) > maxAge
    }

    /// The SteamID64 of `account`, from the shared Steam client's `loginusers.vdf`, where Cellar
    /// writes it at sign-in. Matched case-insensitively, as Steam matches account names.
    static func steamID(for account: String, loginUsers: TextVDF?) -> String? {
        guard let users = loginUsers?.block("users") else { return nil }
        for entry in users.entries {
            guard case .block(let user) = entry.value,
                  user.string("AccountName")?.caseInsensitiveCompare(account) == .orderedSame,
                  isSteamID(entry.key) else { continue }
            return entry.key
        }
        return nil
    }

    /// A SteamID64 for an individual account: 17 digits starting 7656119.
    static func isSteamID(_ text: String) -> Bool {
        text.count == 17 && text.hasPrefix("7656119") && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// The full-size picture's address in a Community profile's XML — only if it is served from
    /// Steam's own image hosts over HTTPS. Anything else is ignored rather than downloaded.
    static func avatarURL(inProfileXML xml: String) -> URL? {
        guard let open = xml.range(of: "<avatarFull>"),
              let close = xml.range(of: "</avatarFull>", range: open.upperBound..<xml.endIndex) else { return nil }
        var value = String(xml[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("<![CDATA["), value.hasSuffix("]]>") {
            value = String(value.dropFirst("<![CDATA[".count).dropLast("]]>".count))
        }
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", let host = url.host?.lowercased(),
              host == "steamstatic.com" || host.hasSuffix(".steamstatic.com")
                || host.hasSuffix(".steamcommunity.com") || host.hasSuffix(".akamaihd.net")
        else { return nil }
        return url
    }

    /// Fetches the signed-in account's picture if it is missing or stale. Blocking (curl); call it
    /// off the main actor. Returns the file when one is there afterwards.
    @discardableResult
    public static func refreshIfStale() -> URL? {
        guard let account = SteamAccount.state.accountName else { return nil }
        guard isStale(for: account) else { return localFile(for: account) }
        guard let loginUsers = try? String(contentsOf: Paths.sharedSteam.appendingPathComponent("config/loginusers.vdf"),
                                           encoding: .utf8),
              let id = steamID(for: account, loginUsers: TextVDF.parse(loginUsers)),
              let xml = try? Downloader.string("https://steamcommunity.com/profiles/\(id)/?xml=1"),
              let picture = avatarURL(inProfileXML: xml)
        else { return localFile(for: account) }
        let target = file(for: account)
        let partial = target.appendingPathExtension("part")
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try Downloader.fetch(picture.absoluteString, to: partial, showProgress: false)
            _ = try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: partial, to: target)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            CellarLog.debug(.account, "Steam avatar not fetched: \(CellarLog.describe(error))")
        }
        return localFile(for: account)
    }

    /// Forgets `account`'s picture, with its sign-in.
    public static func forget(_ account: String, in shared: URL = Paths.shared) {
        try? FileManager.default.removeItem(at: file(for: account, in: shared))
    }
}
