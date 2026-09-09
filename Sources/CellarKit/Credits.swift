import Foundation

/// Who Cellar is built on. One list, shown verbatim by the app's About panel and Settings › About,
/// so the two can never disagree about whom to thank.
///
/// Wine is first on purpose: everything Cellar does happens inside Wine. Cellar adds a runner
/// catalogue, bottles, profiles and a launcher on top — the Win32 implementation is all theirs.
public struct Credit: Sendable, Equatable {
    public let name: String
    /// One plain sentence: what the project does for Cellar.
    public let role: String
    public let license: String
    public let url: URL
    /// Where the source lives, when that is a different place from the project's front door.
    public let sourceURL: URL?

    public init(name: String, role: String, license: String, url: String, sourceURL: String? = nil) {
        self.name = name
        self.role = role
        self.license = license
        self.url = URL(string: url)!
        self.sourceURL = sourceURL.map { URL(string: $0)! }
    }
}

public enum Credits {
    /// Cellar's own one-line description, as the About panel states it.
    public static let tagline =
        "Run Windows games on Apple Silicon — a Proton-like layer over Wine + D3DMetal. " +
        "Sign in once per store, then install and play."

    public static let wine = Credit(
        name: "Wine",
        role: "The Windows compatibility layer every game runs in. Cellar is a launcher over it; Wine is the work.",
        license: "LGPL-2.1+",
        url: "https://www.winehq.org/",
        sourceURL: "https://gitlab.winehq.org/wine/wine")

    /// Everything else, in the order a player meets it: the Wine builds Cellar installs, the
    /// graphics backend, then the tools that fetch games.
    public static let all: [Credit] = [
        wine,
        Credit(name: "CodeWeavers · CrossOver",
               role: "The macOS patches — the Mac driver above all — that make Wine run well on a Mac. Cellar uses only the public LGPL sources, never CrossOver itself.",
               license: "LGPL-2.1+",
               url: "https://www.codeweavers.com/crossover",
               sourceURL: "https://github.com/CodeWeavers/wine"),
        Credit(name: "WineForge",
               role: "The default runner: Wine 11 with the CrossOver patches and its own WFUSync fast sync, prebuilt for macOS.",
               license: "LGPL-2.1+",
               url: "https://github.com/Alien4042x/WineForge"),
        Credit(name: "Sikarugir",
               role: "The Wine 10 runner and the wrapper template Cellar takes D3DMetal from.",
               license: "LGPL-2.1+",
               url: "https://github.com/Sikarugir-App"),
        Credit(name: "marzent · msync",
               role: "Mach-semaphore fast sync for Wine on macOS — the Wine 10 runner's fast path.",
               license: "LGPL-2.1+",
               url: "https://github.com/marzent/wine-msync"),
        Credit(name: "Gcenx",
               role: "The Game Porting Toolkit runner build, and years of Wine-on-macOS packaging.",
               license: "LGPL-2.1+",
               url: "https://github.com/Gcenx"),
        Credit(name: "Apple D3DMetal",
               role: "DirectX 11/12 → Metal. Never bundled by Cellar; grafted from a runner at run time under Apple's non-commercial grant.",
               license: "Apple (proprietary)",
               url: "https://developer.apple.com/games/game-porting-toolkit/"),
        Credit(name: "DepotDownloader",
               role: "Downloads the games you own from Steam without the Windows client.",
               license: "GPL-2.0",
               url: "https://github.com/SteamRE/DepotDownloader"),
        Credit(name: "swift-argument-parser",
               role: "Parses the cellar command line.",
               license: "Apache-2.0",
               url: "https://github.com/apple/swift-argument-parser"),
    ]

    /// The non-affiliation line, in one place.
    public static let nonAffiliation =
        "Cellar is GPL-3.0 and not affiliated with the Wine project, Apple, Valve, Blizzard, CodeWeavers or any game publisher."
}
