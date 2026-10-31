import CellarDomain
import SwiftUI
import AppKit
import CellarKit
import CellarUI

/// Where a game's artwork comes from, per store.
///
/// Steam publishes cover and banner art for every AppID on a public CDN, which is why the library
/// looks like a storefront for Steam titles. No other store Cellar speaks to does: Blizzard's art
/// is not addressable by product code and is not ours to hotlink. So the chain is: art the profile
/// declares → the store's public CDN if it has one → Cellar's own generated cover. The last link is
/// not a placeholder to be embarrassed about; it is the design for every store but one.
enum Artwork {
    static func steamCDN(_ appID: Int?, _ kind: String) -> URL? {
        guard let appID else { return nil }
        return URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/\(kind)")
    }

    /// 600×900 cover. `artworkAppID` is nil for stores with no public artwork.
    static func portrait(_ game: GameSummary) -> URL? {
        game.artPortraitURL.flatMap(URL.init(string:))
            ?? steamCDN(game.artworkAppID, "library_600x900.jpg")
    }

    /// Wide banner behind the detail header.
    static func hero(_ game: GameSummary) -> URL? {
        game.artHeroURL.flatMap(URL.init(string:))
            ?? steamCDN(game.artworkAppID, "library_hero.jpg")
    }
}
