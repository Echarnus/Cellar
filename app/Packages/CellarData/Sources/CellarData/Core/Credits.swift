import CellarDomain
import Foundation

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
    /// graphics backends inside them, then the tools that fetch games.
    ///
    /// `docs/LEGAL.md` → *License hygiene*: every publisher Cellar downloads from is named here, and
    /// `CreditsTests` holds that true.
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
        Credit(name: "DXMT",
               role: "DirectX 11 → Metal, the open alternative to D3DMetal. Ships inside the Sikarugir template.",
               license: "zlib",
               url: "https://github.com/3Shain/dxmt"),
        Credit(name: "DXVK",
               role: "DirectX 9/10/11 → Vulkan, the fully open graphics path. Ships inside the Sikarugir template.",
               license: "zlib",
               url: "https://github.com/doitsujin/dxvk"),
        Credit(name: "MoltenVK",
               role: "Vulkan → Metal, underneath DXVK. Ships inside the Sikarugir template.",
               license: "Apache-2.0",
               url: "https://github.com/KhronosGroup/MoltenVK"),
        Credit(name: "GStreamer",
               role: "Plays games' intro and cut-scene videos inside Wine. Ships inside the runners.",
               license: "LGPL-2.1+",
               url: "https://gstreamer.freedesktop.org/"),
        Credit(name: "DepotDownloader",
               role: "Downloads the games you own from Steam without the Windows client.",
               license: "GPL-2.0",
               url: "https://github.com/SteamRE/DepotDownloader"),
        Credit(name: "swift-argument-parser",
               role: "Parses the cellar command line.",
               license: "Apache-2.0",
               url: "https://github.com/apple/swift-argument-parser"),
        Credit(name: "Sparkle",
               role: "Keeps Cellar itself up to date: checks for a new release, shows what changed, and installs it when you say so.",
               license: "MIT",
               url: "https://sparkle-project.org"),
    ]

    /// Where Cellar's knowledge about games comes from: the facts in its profiles and the reports
    /// behind its compatibility estimates (`docs/COMPATIBILITY.md`). Credited wherever Cellar
    /// thanks anyone (Kenneth, 2026-11-03: credit where credit is due), each with the terms its
    /// data comes under. `CreditsTests` fails when a source the estimate or
    /// `refresh-evidence.py` reads is missing here.
    public static let sources: [Credit] = [
        Credit(name: "ProtonDB",
               role: "Linux players' reports of how each game runs, read as its summary rating for Cellar's estimates.",
               license: "ODbL 1.0 (database), DbCL 1.0 (contents)",
               url: "https://www.protondb.com",
               sourceURL: "https://github.com/bdefore/protondb-data"),
        Credit(name: "Steam Deck compatibility ratings",
               role: "Valve's Verified, Playable and Unsupported ratings, quoted in Cellar's estimates.",
               license: "Valve's ratings, quoted with attribution",
               url: "https://store.steampowered.com/steamdeck"),
        Credit(name: "AreWeAntiCheatYet",
               role: "Which games' anti-cheat accepts a Windows layer, and which publishers block it.",
               license: "MIT",
               url: "https://areweanticheatyet.com",
               sourceURL: "https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet"),
        Credit(name: "AppleGamingWiki",
               role: "Mac players' reports of games running through CrossOver and Whisky, cited in game notes.",
               license: "CC BY-NC-SA 3.0",
               url: "https://www.applegamingwiki.com"),
        Credit(name: "CodeWeavers Compatibility Center",
               role: "CrossOver's ratings of games on the Mac, cited in game notes.",
               license: "CodeWeavers' ratings, quoted with attribution",
               url: "https://www.codeweavers.com/compatibility"),
        Credit(name: "PCGamingWiki",
               role: "Game facts: engines, graphics, anti-cheat and DRM, checked when a game is added.",
               license: "CC BY-NC-SA 3.0",
               url: "https://www.pcgamingwiki.com"),
        Credit(name: "SteamDB",
               role: "Steam's own app records (executables, install folders, depots), checked when a game is added.",
               license: "Facts, cited with attribution",
               url: "https://steamdb.info"),
        Credit(name: "Steam",
               role: "Cover art and store facts, shown from Steam's own servers; © Valve and each game's publisher.",
               license: "Valve and publishers, shown, never bundled",
               url: "https://store.steampowered.com"),
    ]

    /// The non-affiliation line, in one place.
    public static let nonAffiliation =
        "Cellar is GPL-3.0 and not affiliated with the Wine project, Apple, Valve, Blizzard, GOG, CodeWeavers or any game publisher."
}
