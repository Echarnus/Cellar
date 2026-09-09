# Architecture

Cellar = a **general translation engine** + a **per-game profile database** + a **launch/transparency
layer**. These mirror Proton's three pillars (bundled runtime, per-title fixes, invisible launch),
adapted to where macOS differs from Linux.

## The translation stack

```
   Windows game  —  .exe, x86-64, DirectX (e.g. Planet Coaster 2: DX12, COBRA engine)
                            │
        ┌───────────────────▼───────────────────┐
        │   Wine 11  (LGPL-2.1+)                 │  reimplements Win32 → macOS (NOT an emulator)
        │   single-binary WoW64                  │
        └───────────────────┬───────────────────┘
                            │   DirectX calls branch here:
            ┌────────────────┴─────────────────┐
   PATH A (default, fastest)         PATH B (FOSS-only, no Apple ID)
   D3DMetal  (Apple, proprietary,    DXVK / VKD3D-Proton  (DX → Vulkan)
   user-supplied)  DX11/12 → Metal             │
            │                        MoltenVK (Apache-2.0)  Vulkan → Metal
            └────────────────┬─────────────────┘
                            ▼
                    Metal  (Apple GPU API)
                            │
                ┌───────────▼───────────┐
                │  Rosetta 2             │  x86-64 → ARM64 (whole process)
                └───────────┬───────────┘
                            ▼
                     Apple Silicon GPU / CPU
```

- **Path A (Wine + D3DMetal)** is the mature, modern-game path on Apple Silicon. D3DMetal goes
  straight DirectX → Metal (one hop), and is proprietary, so it is **user-supplied** (`cellar gptk
  import`), never bundled.
- **Path B (Wine + DXVK/VKD3D + MoltenVK)** is fully open-source and needs no Apple download. It is
  the right choice for DirectX 9 / older titles (D3DMetal has no DX9) and as a fallback, but
  MoltenVK's incomplete Vulkan conformance makes it weaker for modern DX12 titles.
- **Backend is per-profile** (`d3dmetal | dxvk | vkd3d | wined3d | dxmt`), so each game uses what
  works best for it.

## Why not literally Proton?

Proton is a Linux stack twice over: it runs over **native Vulkan** (macOS has only Metal), and it
plugs into the **Linux** Steam client's compatibility-tool hook (**absent on the macOS client**).
So Cellar reproduces the *experience*, not the binary: it **owns the launch path** the way
Steam-on-Linux does, using Wine + D3DMetal and per-game profiles.

## Components

| Layer | Module | Responsibility |
|---|---|---|
| Engine core | `CellarKit` | environment detection, bottles (prefixes), runners, profile discovery |
| CLI | `cellar` | thin ArgumentParser front-end over `CellarKit` |
| Runner | `Runner.swift` | download/pin prebuilt LGPL Wine; graft D3DMetal; assemble backend env |
| GPTK import | `Gptk.swift` | copy user-supplied D3DMetal from Apple's `.dmg` into the local cache |
| **Store layer** | `Store.swift` + `Steam.swift` / `BattleNet.swift` | stand the game's own storefront client up inside the bottle |
| Profile DB | `profiles/` + (Phase 2) registry sync | per-game config, generality |
| GUI | `CellarApp` | native SwiftUI app over the same `CellarKit` core |

## The store layer

A game does not just need Wine — it needs *the client it was bought from*, running inside the same
bottle. Each profile names one with `store = "…"`, and that single field decides the whole pipeline:
which installer `cellar setup` runs, what "installed" and "signed in" even mean, how a launch is
issued, and what the app says to the player.

| | **Steam** (`SteamBottle`) | **Battle.net** (`BattleNetBottle`) | **GOG** (`GOG*`) | **Standalone** |
|---|---|---|---|---|
| Client in the bottle | yes | yes | **none** | none |
| Installer | `SteamSetup.exe /S` — silent | `Battle.net-Setup.exe` — **no silent switch**; a window opens and the player clicks through | the game's own Inno Setup installer, `/VERYSILENT` | none |
| Client binaries | `steam.exe` | `Battle.net Launcher.exe` bootstraps `Battle.net.exe` | none | none |
| Games addressed by | numeric AppID | product code (`Fen` = Diablo IV) | `gog_product_id` | a path |
| Authentication | in the client's own window | in the client's own window | **OAuth 2.0 token Cellar holds** (keychain) | none |
| "Signed in?" | readable — `config/loginusers.vdf` | **not observable**; folded into "open the client" | readable — Cellar owns the token | n/a |
| "Installed?" | `appmanifest_<id>.acf`, `StateFlags 4` | the profile's `install_dir` + `exe` on disk | the exe on disk | the exe on disk |
| Install a game | `steam://install/<id>` | no drivable URL — open the client | Cellar downloads + runs the installer | DepotDownloader |
| Launch | `steam://rungameid/<id>` into a `-silent` client | `Battle.net.exe --exec="launch <product>"`, client warmed first | run the exe — nothing beside it | run the exe |
| Public artwork | yes, per AppID | none a launcher may hotlink | yes, from the product API | none |

Three consequences worth stating plainly, because they shape the UI as much as the code:

- **Cellar never invents a state it cannot check.** Battle.net gets no sign-in step and no ✓ or ✗
  beside "account", because Blizzard does not publish one. `GameStore.descriptor.canDetectSignIn`
  carries that fact to every surface. Accounts asks only whether the player *has* an account there —
  labelled "Added by you", so the badge names who is making the claim.
- **Cellar announces a pause it cannot remove.** Because Blizzard ships no silent installer, setup
  warns before the window appears rather than looking hung. GOG's installer *is* silent, which is its
  own kind of surprising, so that pause is announced too.
- **Signing in is account-level, not game-level.** `StoreDescriptor.authStyle` says which of the two
  shapes a store has — `.inClientWindow` (Steam, Battle.net) or `.cellarHeldToken` (GOG) — and the
  Settings screen is built from it. See *One Steam, every bottle* and *The one Steam sign-in* below
  for why this stopped being a per-game question for Steam too.

All of it lives in `StoreDescriptor`, so the CLI and the app say the same thing without either knowing
about the other. Adding a store is: a `GameStore` case, a `*Bottle` type, a branch in `Game.setUp`
and `Game.launch`, and a CLI command group.

### One Steam, every bottle

A bottle is per-game on purpose: its own registry, its own runner, its own Wine version. The Steam
*client* is not per-game — it belongs to the account. Giving each bottle its own copy meant a 1.4 GB
download and **a fresh sign-in for every game**, and a game owned once could be downloaded twice.

So the client lives once, in `shared/steam`, and every Steam bottle gets a **symlink** at the Windows
path Steam expects (`C:\Program Files (x86)\Steam`). Because that Windows path is identical in every
bottle, Steam's own registry keys and `libraryfolders.vdf` stay valid, and every reader
(`loggedInAccount`, the appmanifest lookups) resolves through the link with no code change.

The alternative — one shared *prefix* for all Steam games — was rejected: a prefix is bound to a Wine
version, so it would force every Steam game onto one runner and give up per-game runner tuning, which
is the point of bottles.

`cellar steam share` migrates an existing install and is idempotent. It never deletes a download: the
richest existing install (a signed-in one first, then the largest) is *promoted* into the shared one
by a same-volume rename, and any other is moved aside as `Steam.superseded-<timestamp>` with the path
printed so the player reclaims the space deliberately.

### The one Steam sign-in

`SteamAccount` is the whole of it: Steam's own device-authorization flow
(`IAuthenticationService/BeginAuthSessionViaQR`), run once from Settings, approved in the Steam
mobile app, nothing typed. That single session answers **both** questions Cellar has of Steam —
which games this account may have, and hand them over — so there is no Web API key, no separate
download credential, and no per-game sign-in.

Three things had to be true for one to be enough:

- **The token is DepotDownloader's, not Cellar's.** It obtains it and keeps it in .NET *isolated
  storage*, whose location is derived from the process's `HOME` and hashed. Cellar pins `HOME` to a
  directory it owns (`tools/depotdownloader/home`) so the session can be seen, reused and genuinely
  revoked. Before that, Cellar looked for an `account.config` beside the binary that .NET never
  writes there — so "signed in" was permanently false, sign-out did nothing, and every download
  asked for a fresh QR scan. That single wrong path is what made the sign-in feel like three.
- **The account name is captured, not guessed.** A stored token can only be looked up by the
  username it was stored under, so the name is parsed out of DepotDownloader's own success line and
  recorded. That is what makes every later run silent.
- **Expiry is learned by being refused.** Cellar never holds the token, so it cannot read an expiry
  date and does not pretend to: it watches for `Access token was rejected (…)`, keeps Steam's own
  word for the reason, and turns the next screen into "sign in again" rather than a failed download.
  Age is reported instead of a countdown — these sessions last about 200 days, and Cellar starts
  mentioning it at 180.

**The in-bottle Windows client is not a second account.** It is a runtime dependency of the games
whose DRM talks to a running Steam (`config/loginusers.vdf`, one window, once, shared by every
bottle). A token cannot be injected into its credential store — that is machine-keyed inside
`config.vdf` — so those games still sign in there, and Cellar reports it as a fact about the machine
rather than as another sign-in to perform.

### Your games, not the catalogue

`StoreLibrary` decides what is in the library, once, so `cellar library` and the app cannot drift.
The gate asks two questions in order. **Is the store connected?** — nothing is listed for a store
Cellar has no account for, whatever it can or cannot say about ownership. For Steam and GOG that is
a credential Cellar holds; for Battle.net it is the player's own word, added once in Accounts
(`StoreLibrary.BattleNetAccount`), because Blizzard publishes nothing to read. Without that first
question, Diablo IV was listed on a Mac that had never opened Battle.net.

**Then: do they own it?** Ownership has **three** answers, not two — `.owned`, `.notOwned`,
`.unknown` — and the gate splits the last one on whether the store *could* ever answer: a store that
can (Steam, GOG) hides its games until asked, with the fix attached; a store that never can
(Battle.net) shows them once connected, saying plainly that nobody checked.

Steam is asked per game, by running the download's own licence check and stopping the moment it
answers (`DepotTool.access`). That is deliberately the *same* question as "can I install this",
asked of the same credential that would do the installing — so it covers a lapsed family-share or a
region lock, which a list of owned app ids would not. Answers are cached under `shared/libraries/`,
keyed to the account, because `Game.summaries()` runs on every library refresh and must never make a
network call.

`StoreLibrary.gatingStore` handles the one crossover: a `standalone` profile carrying a
`steam_appid` (Stardew Valley) needs no client but is still fetched from the player's Steam account,
so **Steam** gates it.

DepotDownloader only ever *draws* the QR challenge, as terminal ASCII, and prints no URL — so
`SteamQRCode.swift` reads the drawing back into a module matrix and the app renders it at a scannable
size. Format, measured not assumed: two characters per module, four-module quiet zone, one text line
per module row. There is a round-trip case in `cellar selftest`.

## On-disk layout

```
~/Library/Application Support/Cellar/
├── runners/     # installed Wine builds
├── prefixes/    # one bottle per game (pfx/ + bottle.toml)
├── shared/
│   └── steam/   # THE Windows Steam install — every Steam bottle symlinks to it
├── tools/
│   └── depotdownloader/   # native-arm64 DepotDownloader + its stored Steam session
├── cache/
│   ├── gog/     # downloaded GOG installers, resumable
│   └── d3dmetal/  # user-supplied Apple D3DMetal (never in the repo)
├── profiles/    # user/registry-synced profiles (these win over the shipped database)
└── logs/
```

The profile database also ships *inside* the installed app (`Cellar.app/Contents/Resources/profiles`)
and beside an installed CLI (`<prefix>/share/cellar/profiles`). Those are searched **last**, so a
shipped update never overwrites a profile the player has edited by hand.

## The Planet Coaster 2 path (worked example)

1. `cellar setup` — installs the **GPTK runner** (Wine 7.7 + D3DMetal, fetched from Gcenx),
   creates the `planet-coaster-2` bottle, runs `wineboot --init`, sets Windows 10, and installs the
   **Windows Steam client** into the bottle (pinning client updates via `steam.cfg`).
2. `cellar steam open planet-coaster-2` — Steam opens inside the bottle with the load-bearing macOS
   flags (`-cef-force-32bit -allosarches -no-cef-sandbox`). Log in (Steam Guard/2FA works). This
   bypasses the greyed-out Mac Install button — the bottle *is* Windows to Steam.
3. Install PC2 from the in-bottle Steam (`steam://install/2688950`). Denuvo **Anti-tamper** DRM runs
   untouched inside the layer.
4. `cellar launch planet-coaster-2` — launches via `steam://rungameid/2688950` with the D3DMetal env
   (`D3DM_SUPPORT_DXR`, `ROSETTA_ADVERTISE_AVX`, msync). D3DMetal is the builtin renderer in the GPTK
   Wine build — **no `WINEDLLOVERRIDES` needed**.
5. Optional `cellar steam add planet-coaster-2` — emits `~/Applications/Planet Coaster 2.app` and a
   non-Steam shortcut so it shows in the native Steam library.

## The Diablo IV path (worked example — Battle.net)

1. `cellar setup --profile diablo-4` — installs the **WineForge runner** (Wine 11.17 + D3DMetal 3.0),
   creates the `diablo-4` bottle, `wineboot --init`, Windows 10, then downloads Blizzard's installer
   and runs it with `--lang=enUS --installpath="C:\Program Files (x86)\Battle.net"`. **Its window
   opens and needs a few clicks** — Cellar says so before it happens. Afterwards Cellar stops the
   client and writes `Battle.net.config` with hardware acceleration and streaming off, which is what
   makes the login form render under Wine instead of a spinning logo.
2. `cellar battlenet open diablo-4` — the client opens. Sign in, install Diablo IV from inside it.
   There is no install URL a launcher can drive, so Cellar takes you there rather than pretending.
3. `cellar launch diablo-4` — brings `Battle.net.exe` up and waits for it, then issues
   `--exec="launch Fen"` and supervises the startup, retrying through the D3DMetal race
   (`ProcessWatch.superviseStart`, shared with the Steam path). Diablo IV is always-online, so the
   client stays running alongside the game.
4. Quit the game and Cellar kills the client, its `Agent.exe` and helpers, then `wineserver -k` —
   the whole layer closes with the game.
