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
| Uninstall | delete the install dir **inside the shared library**, plus its manifests; close the client first | delete the install dir; the client re-offers it as an install | run the game's own Inno uninstaller, then delete | delete the depot dir |
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
### Keeping the client out of the Dock

Wine's Mac driver gives a Dock icon to every Windows process that shows a window — it calls
`-[NSApplication setActivationPolicy:Regular]` the first time one is ordered front. For a game that
is correct. For Steam it is not: Cellar starts Steam so a game can run, and a second icon beside
Cellar's advertises plumbing the player never asked for.

Wine has no setting for this. The Mac driver's entire option list under `Software\Wine\Mac Driver`
(`RetinaMode`, `EnableAppNap`, `CaptureDisplaysForFullscreen`, …) has no dock key, and macOS refuses
to let one process change another's activation policy — `TransformProcessType` on a foreign
`ProcessSerialNumber` returns `procNotFound`. The decision can only be changed inside the process
making it, so Cellar inserts one (`Shim/cellar-dock-shim.c`, via `DYLD_INSERT_LIBRARIES`) that turns
that process's request for *Regular* into *Accessory*: windows, focus and keyboard all keep working,
and only the Dock tile and the ⌘-Tab entry go away.

Two rules keep it honest:

- **Only the client, never the game.** `CELLAR_DOCK_HIDE` names the client's own executables
  (`StoreDescriptor.clientProcessNames` — `steamwebhelper.exe` is the one that actually takes the
  icon; `steam.exe` claims one too once it has shown a window). Every other process in the launch is
  left alone, so a game — or anything Cellar has not been told about — keeps its icon by default.
- **Only when the client is scaffolding.** `DockPresence` splits the two intents. Starting a game is
  `.hidden`. Choosing *Open Steam* is `.visible`, because a window the player has to come back to
  needs a Dock icon to come back *to*.

The shim is a universal dylib (a runner may be x86_64 under Rosetta or arm64), built by
`Scripts/build-dock-shim.sh` and installed beside the CLI. If it is missing, `DockShim.environment`
returns nothing and launches behave exactly as they did before — a cosmetic feature must never be
able to stop a game from starting.

### Removing a game

`Uninstall.swift` is the mirror image of setup, and it is deliberately the most cautious code in the
project. A game's footprint is spread across places the player never chose — a Steam library shared
by every Steam game, a Wine bottle, a generated `.app`, an icon in the cache, a line in the native
Steam client's `shortcuts.vdf` — so removal is a **plan first**: `Uninstall.plan(for:scope:)` resolves
and measures every path, records what deliberately survives, and raises blockers. Only then does
`perform` delete anything, re-validating each path as it goes.

Two scopes: `.game` (the game and what Cellar generated for it) and `.bottle` (that, plus the Wine
prefix and the client inside it). The rules that keep it safe:

- **The shared Steam install is never a target.** `isDeletable` refuses `shared/steam`, `steamapps`,
  `steamapps/common`, every `Paths.*` root and every bottle's `drive_c` roots, and only ever allows a
  path *inside* a directory Cellar owns. There are assertions for all of them in `cellar selftest`.
- **The bottle's `Steam` symlink is unlinked, never followed** — it points at the shared install that
  holds the sign-in and everybody else's games.
- **A `.app` is deleted only if it carries Cellar's own bundle identifier**, so a game's real app of
  the same name in `~/Applications` is left alone.
- **A shared bottle blocks the `.bottle` scope**, naming the other profiles that live in it.
- **A running game blocks removal; a running client is closed first**, announced before it happens.
- Store-specific behaviour — what survives, what the client does afterwards, whether it must be
  closed — is in `StoreDescriptor`, like every other per-store difference.

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
    ├── cellar.log      # the rolling event log (+ .1, .2 — the two files it rolls into)
    ├── game-<slug>.log # Wine's own output for a direct launch
    └── steam-*.log / battlenet-*.log   # Wine's output for a store client
```

The profile database also ships *inside* the installed app (`Cellar.app/Contents/Resources/profiles`)
and beside an installed CLI (`<prefix>/share/cellar/profiles`). Those are searched **last**, so a
shipped update never overwrites a profile the player has edited by hand.

## Folder permissions: asked once, up front

`wineboot --init` builds the Windows user profile with *Documents*, *Desktop* and *Downloads*
symlinked to the real `~/Documents`, `~/Desktop`, `~/Downloads` — which is what you want, since a
save then lands where Finder and Time Machine can see it. Those three are exactly the folders macOS
gates behind a privacy prompt, so left alone the player meets *"Cellar.app would like to access files
in your Documents folder"* halfway through an install, with nothing on screen explaining it.

So Cellar owns the timing instead (`Sources/CellarKit/HomeFolders.swift`):

- **The app asks on first launch** (`WelcomeView`) — the same three dialogs macOS would have shown,
  together, before anything is at stake, under a sentence saying what each folder is for. The
  `NS*FolderUsageDescription` keys in `Info.plist` put that reason inside the system dialog too.
  Re-openable afterwards from **Settings → Review folder access…**.
- **The CLI announces it** instead: `cellar setup` warns before `wineboot` runs, since a terminal
  has no first-run screen. `cellar doctor` reports the state — naming *which* process it speaks for,
  because a `cellar` in Terminal is covered by Terminal's grant, not Cellar.app's.
- **"Don't Allow" is honoured, not fought.** `redirectDeniedUserShellFolders` replaces the symlink
  for a refused folder with a real directory inside the bottle, so the game writes its saves there
  rather than failing silently. Only Wine's own symlink is ever replaced — never a directory that
  already holds saves.

There is no API for reading the privacy database, so *asking is the only way to find out*: reading
the directory **is** the request. That is the whole reason the timing is Cellar's to choose.
## The rolling log

Cellar drives Wine, a store client and a Windows game, and none of them report back. When a player
says "it crashed", the only thing that can answer is what Cellar wrote down at the time — so it
writes down every set-up step, launch, retry, play session and failure, from **both** the CLI and
the app, into one file.

| Piece | Where | What it does |
|---|---|---|
| `CellarLog` | `Sources/CellarKit/Log.swift` | The writer. One entry per line, four levels (`debug` `info` `warn` `error`), a category and an optional subject (usually the game slug). Rolls at 512 KB into `.1` and `.2`, so the history is capped at ~1.5 MB and can always be sent. |
| `Diagnostics` | `Sources/CellarKit/Diagnostics.swift` | Lifecycle bookkeeping, play sessions, macOS crash-report lookup, and the exportable report. |
| `cellar logs` | `Sources/cellar/Commands/LogsCommand.swift` | `show` (filter by level or game), `path`, `export`, `clear`. |
| Settings → Diagnostics | `Sources/CellarApp/SettingsView.swift` | The same export, one button, saved to the Desktop. |

What it records, and why each one is there:

- **App started / quit.** The app writes a marker file while it runs and removes it on a clean quit,
  so the *next* start can say the previous session ended abnormally — and look for a macOS crash
  report filed in that window. This is the only honest way Cellar can know it crashed.
- **A play session.** `Game.launch` records the route it took; `waitForExitThenShutDown` records how
  long the game ran. An exit inside 90 seconds is logged as a **warning** with the tail of the Wine
  log and any crash report from that window — Cellar cannot see a Windows exit code through Wine, so
  it never *claims* a crash, it reports what it observed.
- **Every progress line.** The `progress:` closures the CLI prints are wrapped, so what the player
  read is what the log holds — set-up steps, the D3DMetal start-race retries, install progress.
- **Every failure.** `Cellar.main` wraps the CLI's entry point, so any command that exits non-zero
  is logged with the invocation and the error the player was shown.

`cellar logs export` folds all of that plus the machine, the runners, the bottles and the tails of
the Wine logs into one text file for a bug report. It is **redacted**: the home path becomes `~`, the
user name becomes `<user>`, and sign-in *state* is reported, never account names.

Command lines are redacted **fail-closed**, in `Diagnostics.redactCommandLine`: an option's value is
kept only if the option is on a short allowlist of diagnostic ones (`--profile`, `--level`,
`--output`…), and every other value — including options that do not exist yet — becomes
`<redacted>`. Positional words (the subcommand, the profile slug) are kept, because no command takes
a credential positionally and they are what makes a line readable.

The first version listed *sensitive* names instead and matched only `--long` options, so
`fetch-depot -u <steam account>` and `gog login --code <oauth code>` reached the export in
plaintext — under an on-screen promise that they had been removed. A list you must remember to
extend leaks every option nobody thought of; the allowlist cannot. `cellar selftest` now drives the
real formatter in every spelling ArgumentParser accepts (`-u v`, `-uv`, `--username v`,
`--username=v`, and an option deliberately not on any list).

`CELLAR_LOG_LEVEL` sets the floor (`off` disables the file entirely); `CELLAR_LOG_STDERR=1` mirrors
entries to stderr while developing.

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
