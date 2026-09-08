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
| `Scripts/gen-site.py` → `tomllib` | Real TOML — **only on Python 3.11+** | The site, in CI |
| `Scripts/gen-site.py` → hand-rolled fallback | ~20 lines of regex | The site, **on this machine** (system `python3` is 3.9) |
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
- **`store` decides the whole pipeline** — `steam` | `battlenet` | `standalone`. It selects which
  client `cellar setup` installs, what "installed" and "signed in" mean, how a launch is issued, and
  the words the player reads. Steam games are addressed by `steam_appid`; Battle.net games by
  `product_code` + `install_dir` + `exe` (Blizzard publishes no numeric id and keeps its install
  locations in a binary database Cellar does not parse).
- **`[compatibility]`** — `anticheat`, `drm`, `requires_account`, `online`, `status`, `notes`.
- **`[runner]`** — `id`, `windows_version`. **`[graphics]`** — `backend`, `fallback_backend`.
- **`[install]`** — `method`, plus the id the method needs.
- **`[legal]`** — `drm_circumvention = "never"`. It is never anything else.

## Vocabularies the tooling actually knows

`gen-site.py` maps these to labels and CSS classes; a value outside the set silently falls back:

- `status`: **`playable` | `experimental` | `untested`**. An unknown value renders as *Untested*.
- `store`: **`steam` | `battlenet` | `standalone`**. An unknown value is treated as Steam — which
  would put a Battle.net game down the Steam pipeline. Spell it exactly.

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
  product code and why `MTL_DEBUG_LAYER=1` is on. A profile is documentation that happens to be
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
  in `Resources/` is a hard-rule violation ([`../AGENTS.md`](../AGENTS.md)). If a game has no art,
  the app draws a deterministic `GeneratedCover` — that is the intended fallback, not a bug.

## Where profiles are found at runtime

User/registry profiles in `~/Library/Application Support/Cellar/profiles/` **win** over the ones
shipped inside `Cellar.app` and beside an installed CLI, which are searched last. That ordering is
deliberate: a shipped update must never overwrite a profile the player edited by hand. Duplicate
slugs are de-duplicated in that priority order (`ProfileStore.all()`).

## Verify

1. `python3 Scripts/gen-site.py` succeeds and the game's card renders — correct store label, status
   badge, and cover.
2. `swift run cellar profiles` (and the app's library) lists it, and `cellar launch <slug>
   --print-env` shows the `[env]` values actually reaching Wine.
3. Check the fields you added survive **both** parsers — no `#` in values, no arrays, no duplicate
   key names across sections.
4. If you claimed a `status` better than `untested`, say on what hardware, in `notes`.

Related: [`wine-and-runners.md`](wine-and-runners.md) · [`ux.md`](ux.md) · [`python.md`](python.md) ·
[`web.md`](web.md) · [`../CONTRIBUTING.md`](../CONTRIBUTING.md)
