# Skill: Game profiles (`profiles/*.toml`)

The profile database *is* Cellar's generality — adding a game is adding a file, not writing code.
Best practices for authoring and consuming `profiles/*.toml`. Portable guide; Claude's
auto-discovered copy is `.claude/skills/cellar-profiles/SKILL.md`.

Read [`../AGENTS.md`](../AGENTS.md) and [`../CONTRIBUTING.md`](../CONTRIBUTING.md) first.

## Before you add a field: there are three parsers, and they disagree

This is the single most important thing to know about the format. A profile is read by **three
independent parsers**, none of which is a full TOML implementation:

| Reader | What it is | Scope |
|---|---|---|
| `pages/gen-site.py` → `tomllib` | Real TOML — **only on Python 3.11+** | The site, in CI |
| `pages/gen-site.py` → hand-rolled fallback | ~20 lines of regex | The site, **on this machine** (system `python3` is 3.9) |
| `ProfileStore.fields()` / `.env()` (`Profile.swift`) | Line scanner, no TOML library | Everything Cellar does at runtime |

Consequences you must design around:

- **The site parses differently locally than in CI.** CI runners have Python 3.12+ and take the
  `tomllib` path; Kenneth's Mac has the system Python 3.9 and takes the fallback. A profile that
  renders correctly in one can render wrong in the other. **Regenerate and look, and remember which
  parser you just exercised.**
- **`fields()` is a flat scan that ignores section headers, last value wins.** `[game] product_code`
  and `[install] product_code` are the *same key* to Swift. Today they hold identical values in
  `diablo-4.toml` (as do the two `steam_appid`s in `planet-coaster-2.toml`), so nothing is broken —
  but the moment two same-named keys in different sections diverge, Swift silently takes whichever
  is last in the file. **Don't rely on section scoping for uniqueness.** If two sections genuinely
  need different values, give them different key names.
- **Inline comments are stripped differently.** Swift cuts at the first `" #"` (space-hash); the
  Python fallback cuts at the first `#` **anywhere, including inside a quoted string**. So a value
  like `notes = "crash fixed in patch #3"` becomes `"crash fixed in patch"` on the site and stays
  whole in the app. Keep `#` out of values, and always put a space before an inline comment.
- **Scalars only.** No arrays, no inline tables, no multi-line strings, no nested tables. The Swift
  scanner takes `key = value` on one line and strips surrounding quotes; anything else is silently
  dropped, which reads as "my field did nothing".
- **`[env]` is the one section Swift reads *as* a section** (`ProfileStore.env()`), and its values are
  used verbatim as environment variables.

If you need real TOML semantics, that is the Phase 2 typed loader — write it properly, don't extend
the scanners.

## Required shape

Copy the closest existing profile: `planet-coaster-2` for Steam, `diablo-4` for Battle.net.

- **`[game]`** — `slug` (must equal the filename), `name`, `developer`, `engine`, `graphics_api`,
  `architecture`, `released`, and **`store`**.
- **`store` decides the whole pipeline** — `steam` | `battlenet` | `gog`. It selects which
  client `cellar setup` installs, what "installed" and "signed in" mean, how a launch is issued, and
  the words the player reads. Steam games are addressed by `steam_appid`; Battle.net games by
  `product_code` + `install_dir` + `exe` (Blizzard publishes no numeric id and keeps its install
  locations in a binary database Cellar does not parse). Every game comes from a store: a DRM-free
  Steam game is still `steam`, with `needs_live_session = false` so Cellar downloads the depot and
  runs the exe without standing Windows Steam up in the bottle.
- **`[compatibility]`** — `anticheat`, `drm`, `requires_account`, `online`, `status`, `notes`, and optionally
  `controller = "full" | "partial" | "none"` — only what you saw a pad do in this game under Cellar.
  Optional `wheel = "full" | "steering" | "untested" | "none"` — what a racing wheel did in this
  game (`full` includes force feedback; `steering` is steering and pedals without it), shown as the
  *Racing wheel* row; only `untested` or `none` while the game's own `status` is `untested`. With it,
  `wheel_setup` — the in-game steps that bind a wheel, shown verbatim on the game page. See
  `assetto-corsa.toml`.
  Optional `network_check` — space-separated `https://` addresses of the game's own online services
  (a workshop, an account server) that `cellar network <slug>` probes on top of the store's. Only
  addresses you have seen the game use or the publisher documents; a guessed host proves nothing.
  Optional `online_hosts` — space-separated host names the game's **own process** talks to
  (`css-api.zaonce.net` for Planet Coaster 2). `cellar verify` fails `game-online` unless the
  running game holds a connection to each one. That is the check that would have caught the PC2
  Workshop (#23), where every bottle probe passed. Name hosts seen in a run (`lsof` on the game's
  process, or its `wine_debug` trace), never guessed ones.
  Optional `crash_processes` — space-separated process names of a crash reporter of the game's own
  that `cellar verify` doesn't already know. Frontier's, Unity's, Unreal's, Wine's debugger and
  Steam's are built in (`CrashSigns`).
- **`publisher_launcher`** (optional) — a publisher's own launcher the game starts through as well as
  its store. Only `"rockstar"` exists: Steam's Rockstar games hand off to the Rockstar Games Launcher,
  which setup installs into the bottle (`RockstarLauncher`). With it, **`start_exe`** — the program to
  start when it is not the game's own process (`PlayRDR2.exe`, Steam's stub); `exe` stays the game
  (`RDR2.exe`), because that is what Cellar watches. An unknown launcher value is refused by
  `Game.plan`. See `red-dead-redemption-2.toml`.
- **`[runner]`** — `id`, `windows_version`. **`[graphics]`** — `backend`, `fallback_backend`.
  `fallback_backend` is live: when a launch starts the game but it never comes up, the launch window
  (and `cellar launch`) offers it once, and a switch that works is kept in the bottle as
  `graphics_backend` (`BackendChoice`), so a profile update never undoes it. `cellar backend <slug>`
  shows or changes it.
- **`[install]`** — `method`, plus the id the method needs.
- **`save_paths`** (optional) — where the game saves, relative to the Windows user folder, `;`-separated
  (`"Documents/My Games/X; AppData/Local/X"`). `SaveBackups` copies only these; without it, every
  folder `SaveGames` counts as a save in the bottle. Only record a path you have seen the game write.
- **`first_run_files`** (optional, `[launch]`) — settings files the game's own launcher writes on its
  first run and the game can't start without, since Cellar starts the game's exe rather than the
  launcher. `;`-separated `source > destination` pairs: the source relative to the folder holding
  `exe`, the destination relative to the Windows user folder, like `save_paths`. Copied before each
  launch only where nothing exists yet (`FirstRunFiles`). Only for a game you have seen fail
  without them: Skyrim SE crashed on every start until `Skyrim.ini` and `SkyrimPrefs.ini` existed.
- **`generated = "true"`** — a draft Cellar wrote itself (`DraftProfile`, `cellar profiles draft`) from an
  installed game's PE header. Drafts live in the player's own profiles, are always `untested`, and the app
  lists them apart. Turning one into a shipped profile means testing it and deleting this line.
- **`[legal]`** — `drm_circumvention = "never"`. It is never anything else.

## Vocabularies the tooling actually knows

`gen-site.py` maps these to labels and CSS classes; a value outside the set silently falls back:

- `status`: **`playable` | `experimental` | `untested`**. An unknown value renders as *Untested*.
  Players' reports arrive as `compatibility-report` issues (the app asks after a session; `cellar
  report <slug>`): a report is evidence to test against, not a status to copy in unverified.
- `store`: **`steam` | `battlenet` | `gog`**, and **required**. Cellar only runs games installed
  through a store — there is no "no store" value and no manual-install path. A profile that leaves
  `store` out or names anything else is refused by `Game.plan` and never reaches the library.

## Honesty rules (these are not style preferences)

The app and the site display these fields **verbatim** to a player deciding whether to spend an
evening on a download. Cellar's whole proposition is that it does not overpromise — see
[`ux.md`](ux.md).

- **`status` describes what you personally ran**, not what you expect. If it has not been launched on
  hardware you have, it is `untested` — `diablo-4.toml` says `untested` and says why, even though
  every source suggests it will work.
- **`notes` names the hardware and OS.** "Menu ~53 FPS at 1512x982 on M5 / macOS 26.5" is a fact;
  "runs well" is not. Record known turbulence too (patch-day crashes, D3DMetal races).
- **State DRM and anti-cheat precisely and separately.** Denuvo is *anti-tamper DRM*, not anti-cheat.
  Kernel-level anti-cheat and user-space protection are different worlds for a translation layer.
  Never write a profile that implies a circumvention.
- **Comment the *why* in the file.** The existing profiles explain, inline, why `Fen` is Diablo IV's
  product code and why `metal_validation = true` is on. A profile is documentation that happens to be
  executable; a bare key-value dump loses the reasoning that makes it maintainable.

## Known schema drift — don't add a fourth spelling

"Does this game need its store client live?" is currently spelled **three** ways:

- `needs_live_session` — **canonical**, read first (`diablo-4.toml`).
- `needs_live_steam` — the original Steam-only spelling, still read as a fallback.
- `requires_live_steam_session` — present in `planet-coaster-2.toml` and **read by nothing at all.**

Write `needs_live_session` in new profiles. Don't delete the legacy readers without migrating every
profile in the same change, and don't invent a fourth name.

## Artwork

- Steam titles get key art for free: the generator derives
  `cdn.cloudflare.steamstatic.com/steam/apps/<appid>/library_600x900.jpg` from the AppID.
- Non-Steam titles must supply `[art] art_portrait` / `art_hero` themselves. Battle.net publishes
  nothing addressable by product code. Diablo IV is *also* sold on Steam, so its profile points at
  that public CDN art — installation and launch still go through Battle.net; only the pictures come
  from Steam.
- **Never bundle store or publisher artwork in the repo.** Hotlinking public CDN art is fine; a JPEG
  in `app/Resources/` is a hard-rule violation ([`../AGENTS.md`](../AGENTS.md)). If a game has no art,
  the app draws a deterministic `GeneratedCover` — that is the intended fallback, not a bug.

## Where profiles are found at runtime

User/registry profiles in `~/Library/Application Support/Cellar/profiles/` **win** over the ones
shipped inside `Cellar.app` and beside an installed CLI, which are searched last. That ordering is
deliberate: a shipped update must never overwrite a profile the player edited by hand. Duplicate
slugs are de-duplicated in that priority order (`ProfileStore.all()`).

## Verify

1. `python3 pages/gen-site.py` succeeds and the game's card renders — correct store label, status
   badge, and cover.
2. `swift run cellar profiles` (and the app's library) lists it, and `cellar launch <slug>
   --print-env` shows the `[env]` values actually reaching Wine.
3. Check the fields you added survive **both** parsers — no `#` in values, no arrays, no duplicate
   key names across sections.
4. If you claimed a `status` better than `untested`, say on what hardware, in `notes`.

Related: [`wine-and-runners.md`](wine-and-runners.md) · [`ux.md`](ux.md) · [`python.md`](python.md) ·
[`web.md`](web.md) · [`../CONTRIBUTING.md`](../CONTRIBUTING.md)
