# Third-Party Licenses & Redistribution Matrix

Everything Cellar uses that it did not write, where it comes from, under what licence, and what that
licence asks of Cellar. Audited October 2026 against the source tree, the release scripts
(`app/Scripts/package.sh`, `app/Scripts/make-dmg.sh`) and every URL Cellar downloads from.

The distinction that decides the obligations is **who distributes the component**:

- **Shipped by Cellar** — inside `Cellar.app`, the CLI zip or the DMG. Cellar is the distributor and
  must meet the licence itself. Licence texts travel with the release in `Legal/` (see
  [`licenses/`](licenses/)).
- **Fetched at run time** — the player's own copy of Cellar downloads it from its publisher, the way a
  browser downloads a file. The publisher is the distributor; Cellar's duty is to credit it honestly,
  point at its source, and never alter it. Nothing in this group is in the repository or a release.

## 1. Shipped by Cellar

| Component | What it does | Licence | Obligation, and how it is met |
|---|---|---|---|
| **Cellar** (`app/src/`, `app/Shim/`, `app/Scripts/`, `profiles/`) | everything below | **GPL-3.0** | Licence text with every binary (`Legal/LICENSE`); corresponding source at the matching tag on GitHub, named in `NOTICE` |
| **swift-argument-parser** (Apple) | parses the `cellar` command line; statically linked | **Apache-2.0 with Runtime Library Exception** | The exception waives §4(a)(b)(d) for compiled use; Cellar ships the text anyway (`Legal/licenses/swift-argument-parser.txt`) and credits it in About |
| **Sparkle 2** (`sparkle-project/Sparkle`, pinned in `Package.swift`) | the app's self-updater; embedded as `Cellar.app/Contents/Frameworks/Sparkle.framework` | **MIT**, plus the bsdiff, sais-lite and ed25519 notices in the same file | Copyright and permission notice with every copy: `Legal/licenses/Sparkle.txt`, `NOTICE`, credited in About. Not in the CLI |
| **SDL 3** and **sdl2-compat** (libsdl.org, pinned in `app/Scripts/build-sdl.sh`) | Cellar's own SDL, loaded by the runner's Wine ahead of the runner's copy so a wheel's force feedback reaches its motor; shipped as `sdl/libSDL3.dylib` + `sdl/libSDL2-2.0.0.dylib` in the app and the CLI zip | **zlib** | Notice kept with every copy: `Legal/licenses/SDL.txt`. Built from the release tarballs, verified by SHA-256; any Cellar patches live in `app/Shim/sdl/` and are marked as such, as zlib §2 asks. `app/Shim/sdl/0001-cellar-fanatec-force-feedback.patch` adds a Fanatec driver whose command encoding is ported from [hid-fanatecff](https://github.com/gotzl/hid-fanatecff), which declares `MODULE_LICENSE("GPL")` (GPL v2 or later in the kernel's terms); its two files are marked **GPL-2.0-or-later**. `app/Shim/sdl/0002-cellar-thrustmaster-force-feedback.patch` adds a Thrustmaster T300-family driver whose command encoding is ported from [hid-tmff2](https://github.com/Kimplul/hid-tmff2) (**GPL-2.0-or-later**), and whose two files carry the same licence; its mode switch is Cellar's own code, written from the USB request numbers and values that Linux's `hid-thrustmaster` documents. So the `libSDL3.dylib` Cellar ships is distributed under GPL-3.0 with Cellar, and its source is that patch on the pinned tarball |
| **Swift runtime / standard library** | language runtime | Apache-2.0 with Runtime Library Exception | Provided by macOS itself; nothing is embedded that needs attribution |
| **Dock shim** (`app/Shim/cellar-dock-shim.c`) | keeps the bottle's client out of the Dock | GPL-3.0 (Cellar's own code) | — |
| **App icon** (`app/Resources/AppIcon.png`) | the keg icon | GPL-3.0 — drawn by Cellar's own `app/Scripts/make-icon.swift` | — |
| **Store marks** (`app/Packages/CellarUI/Sources/CellarUI/Marks/`) | small Steam / Battle.net / GOG marks | Cellar's own vector code; the marks themselves are their owners' trademarks | Nominative use only, non-affiliation in `NOTICE`. No logo file is bundled; see `docs/LEGAL.md` rule 4 |
| **Game profiles** (`profiles/*.toml`) | per-game facts | GPL-3.0 (Cellar's own data) | Facts only — AppIDs, paths, engine. No game files, no artwork |
| **Fonts** | — | — | None shipped. The app uses the macOS system font; the site uses the visitor's system font stack |

That is the complete list. No Wine, DXVK, MoltenVK, D3DMetal or any other runtime is in a Cellar
release.

## 2. Fetched at run time from the publisher

| Component | Fetched from | Licence | Notes |
|---|---|---|---|
| **Wine** — through the runners below | — | **LGPL-2.1+** | Cellar carries no Wine modifications. Credited first in About and `NOTICE`. Source: gitlab.winehq.org |
| **WineForge** runner (default) | `github.com/Alien4042x/WineForge` releases | LGPL-2.1 (Wine) | Wine 11 + CodeWeavers' public macOS patches |
| **Sikarugir** Wine 10 engine + wrapper template | `github.com/Sikarugir-App` releases | LGPL-2.1+ (Wine, wrapper) | The template's `Frameworks/` is where the D3DMetal, DXMT, DXVK and MoltenVK below come from |
| **Gcenx Game Porting Toolkit** runner (legacy) | `github.com/Gcenx/game-porting-toolkit` releases | LGPL-2.1+ (Wine) + Apple (D3DMetal) | Deprecated; kept for experiments |
| **CodeWeavers' Wine patches** (inside the runners) | — | LGPL-2.1+ | Only the public `winecx` sources. Never CrossOver's app, installer or product code |
| **msync** (marzent, inside Sikarugir) | — | LGPL-2.1+ | |
| **Apple D3DMetal** (inside the Sikarugir template / GPTK runner) | as above | **Proprietary — Apple** | Never in Cellar's repo or releases. See *The Apple rule* below |
| **DXMT** (3Shain, inside the Sikarugir template) | as above | zlib/libpng (as DXVK, which it derives from) — confirm against the template's copy before relying on it | Selected by `backend = "dxmt"` |
| **DXVK** (inside the Sikarugir template) | as above | zlib/libpng | Selected by `backend = "dxvk"` |
| **MoltenVK** (inside the Sikarugir template) | as above | Apache-2.0 | Vulkan → Metal under DXVK |
| **GStreamer** (inside the runners) | as above | LGPL-2.1+ | Media playback (intro videos) |
| **Wine Mono / Wine Gecko** | — | GPL/LGPL/MPL mix | Not installed: Cellar switches off Wine's offer to fetch them when it creates a bottle (`Wine.headlessBootOverrides`) |
| **DepotDownloader** 3.4.0 (SteamRE) | `github.com/SteamRE/DepotDownloader` releases | **GPL-2.0** (SteamKit2: LGPL-2.1) | Run as a separate program — an aggregate, not a combined work, so GPL-2.0-only vs GPL-3.0 does not arise. If it is ever bundled, the release must carry its licence and source offer |
| **Steam client** (`SteamSetup.exe`) | Valve's CDN | Proprietary — Steam Subscriber Agreement | Downloaded from Valve and run unmodified inside the bottle, as the player would |
| **Battle.net client** | Blizzard's download URL | Proprietary — Blizzard EULA | Same: Blizzard's own installer, unmodified |
| **Game cover art** | Steam's public CDN (`cdn.cloudflare.steamstatic.com`) | © each publisher | Shown, never stored in the repo or a release, to identify a game the player owns (app) or that a profile covers (site). Nominative use |
| **Game files** | the player's own Steam / Battle.net / GOG account | the game's EULA | Owned games only; DRM runs untouched (`docs/LEGAL.md`) |

## The Apple rule

**Apple's D3DMetal is never committed to this repository and never shipped in a release artifact.**
It reaches the player's Mac inside a community runner that the player's copy of Cellar downloads at
run time (Sikarugir's wrapper template for the default runner), or from Apple's own Game Porting
Toolkit `.dmg` via `cellar gptk import`. The fully open **DXVK → MoltenVK** path needs no Apple
component at all.

Apple's terms for D3DMetal, as this project reads them, allow it to be used and redistributed only for
**non-commercial** purposes, and say nothing clear about third-party launchers fetching it (UTM asked Apple to clarify this in 2026;
there is no public answer yet). That is the one licence in this project that **limits how Cellar
itself may be distributed**: Cellar can be free software that anybody may sell under the GPL, but a
Cellar that *defaults* to D3DMetal should not be sold, bundled into a paid product, or distributed
with it pre-installed. See `docs/LEGAL.md` → *Distributing Cellar*.

## Cellar's own licence

Cellar is **GPL-3.0** ([LICENSE](LICENSE)), which is compatible with every shipped component above
(Apache-2.0 is GPL-3.0-compatible; the Runtime Library Exception makes it moot for compiled code).
Run-time components are separate programs and keep their own licences.

When a new component is added, add a row here, a `Credit` in `app/Packages/CellarData/Sources/CellarData/Core/Credits.swift`, and —
if it ends up inside a Cellar artifact — its licence text in [`licenses/`](licenses/). The test
`CreditsTests` fails if a runner or tool is downloaded from a publisher the credits do not name.
