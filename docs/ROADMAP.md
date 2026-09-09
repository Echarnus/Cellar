# Roadmap

Cellar is built **MVP-first**: a vertical slice that actually runs Planet Coaster 2, then
generalized into a per-game profile system, then given a native GUI.

## Phase 0 — Bootstrap ✅ (current)

- [x] Swift package: `CellarKit` core + `cellar` CLI
- [x] `cellar doctor` — environment diagnostics (Apple Silicon, macOS, Rosetta, brew, gh, disk, D3DMetal)
- [x] `cellar prefix create / list / remove` — bottle management + `bottle.toml`
- [x] `cellar profiles list / show` — profile discovery
- [x] Licensing & legal scaffolding (GPL-3.0, THIRD_PARTY_LICENSES, NOTICE, docs/LEGAL)
- [x] Seed profile: `planet-coaster-2`

## Phase 1 — Single-game PC2 runner (MVP) ✅ (working)

- [x] `cellar runner install <id>` — download a prebuilt runner (GPTK = Wine + D3DMetal, or Wine-Staging)
- [x] Initialize the Wine prefix (`wineboot`) inside a bottle, set Windows 10
- [x] D3DMetal via the GPTK runner (it's the builtin renderer — no DLL overrides needed)
- [x] Download + silently install the Windows Steam client into the bottle (+ pin client updates)
- [x] `cellar setup` — one-command runner → bottle → prefix → Steam (verified end-to-end on M5)
- [x] `cellar steam open / install` — log into the in-bottle Steam, install the game
- [x] `cellar launch planet-coaster-2` — run through the bottle's Steam (DRM/auth) + D3DMetal + Rosetta
- [x] `cellar steam add` — generate a native `.app` + non-Steam shortcut (binary-VDF writer)
- [x] `cellar selftest` — byte-exact checks for the binary-VDF codec, CRC32, shortcut writer
- [x] **Validate PC2 itself** on M5 / macOS 26 — playable via WineForge (Wine 11.17 + D3DMetal 3.0); perf + stability notes recorded (2026-09-07)
- [ ] `cellar gptk import <dmg>` — the spotless user-supplied-D3DMetal path (moved to Phase 2)
- [ ] Real test target (`swift test`) once full Xcode is available (selftest covers it for now)

## Phase 2 — Generalization & profile DB

- [ ] Full TOML profile schema + decoder (adds a TOML dependency)
- [ ] `cellar install --app <id>` driven entirely by a profile
- [ ] `cellar profiles update` — sync from the community registry
- [ ] winetricks integration; per-profile regedits/env
- [ ] ≥5 seed profiles spanning DX9-via-DXVK, DX12-via-D3DMetal, and a 32-bit/WoW64 case
- [ ] Experimental `cellar fetch-depot` — DepotDownloader for owned-game depots

## Phase 3 — Native SwiftUI GUI

- [ ] macOS app over the same `CellarKit` core (no Electron)
- [ ] Prefix UI, profile browser with one-click install, GPTK import wizard (drag-drop, never bundled)
- [ ] Per-game settings (MetalFX / Retina / Esync), live logs
- [ ] Optional "Send to Steam" (non-Steam shortcut) and native-Steam bridge (behind a flag)
- [ ] App signing + notarization

## Phase 4 — More than one store ✅ (Battle.net)

- ✅ `GameStore` + `StoreDescriptor`: a profile names its storefront and that decides setup, install,
  launch, readiness and copy. Steam / Battle.net / standalone.
- ✅ `BattleNetBottle`: install Blizzard's client into a bottle (interactive — it has no silent
  installer), write the `Battle.net.config` that makes its Chromium UI render under Wine, warm the
  client, launch by product code, and tear the whole layer down on exit.
- ✅ `cellar battlenet {open,install,status,app,configure}`, mirroring `cellar steam`.
- ✅ Diablo IV profile (`product_code = "Fen"`), first Battle.net title.
- ✅ App: library grouped by store, vector store marks, per-store copy and notices, a game
  information panel, profile-supplied artwork.
- ✅ The profile database ships inside the app bundle and beside an installed CLI, so a new game
  reaches players without them copying TOML files — user profiles still win.
- ⏳ Verify Diablo IV end-to-end on the M5 (install + play). The profile is `untested` until then.
- ⏳ Further stores when a game needs one: GOG (DRM-free, closest to the standalone path), Epic.

## Phase 5 — Sign in once ✅ (GOG + shared Steam)

The step from "a wrapper you configure" to "a launcher you sign in to".

- ✅ **One Steam install behind every bottle** (`shared/steam` + per-bottle symlink). One sign-in and
  one 1.4 GB client for the whole library instead of one per game; a game owned once is downloaded
  once. `cellar steam share` migrates an existing install without deleting a download.
- ✅ **Steam QR sign-in for downloads** — Steam's own device-authorization flow, nothing typed,
  approved in the mobile app. `cellar steam login`; the app renders the challenge as a real QR
  (DepotDownloader only draws it in ASCII, so Cellar reads that back — `SteamQRCode.swift`).
- ✅ **GOG, with real OAuth** — the store where signing in once genuinely covers everything: no client
  in the bottle, no live session, DRM-free. `cellar gog login / library / install`, tokens in the
  keychain, and a `witcher-3` reference profile.
- ✅ **An Accounts screen** (`cellar accounts`, and ⌘⇧A in the app) — sign-in is an account-level fact,
  so it has an account-level home instead of being rediscovered per game.
- ❌ **Battle.net OAuth: deliberately not done.** Blizzard runs a real OAuth 2.0 provider, but its
  scopes are game-profile data (`wow.profile`, `sc2.profile`, `d3.profile`) — there is no entitlements
  scope and no download scope. It would tell Cellar a BattleTag and nothing it needs. Sign-in stays
  folded into "open the client".

Next in this direction, not yet done:

- Browse the full owned library rather than curated profiles — possible for GOG today (one API call),
  and for Steam via a Web API key. Steam and Battle.net still need a profile to *run* a game.
- Epic Games Store: a genuine OAuth flow (as Legendary/Heroic use), but reverse-engineered against the
  launcher's own client credentials — a bigger surface and a bigger judgement call than GOG's.
- Generate a profile from a store's metadata, so adding a game is not hand-writing TOML.

## Phase 6 — Native ARM64EC runner (the Rosetta exit)

The whole stack below the game is x86-64 today and runs on Rosetta 2. macOS 27 is the last release
with general-purpose Rosetta; macOS 28 (fall 2027) keeps only a subset for "older unmaintained
gaming titles that rely on Intel-based frameworks" — Apple has **not** said a Wine layer qualifies,
so Cellar does not plan as if it does.

The exit is not "stop translating x86" — the game is an x86-64 Windows binary and always will be.
It is **moving the x86 translation from Rosetta into our own layer**: an arm64 Wine hosting an
ARM64EC PE world, with FEX as the emulator behind it. That is exactly the architecture CodeWeavers
shipped as a CrossOver Mac ARM64 preview in July 2026, and both halves are free software
(Wine LGPL-2.1+, FEX MIT), so the free stack can follow it.

Target layering, versus today:

| Layer | Today (Phase 1-3) | Phase 6 |
|---|---|---|
| Wine host binaries | x86-64 Mach-O → Rosetta | **arm64 Mach-O → native** |
| Wine's PE DLLs | x86-64 PE → Rosetta | **ARM64EC PE → native** |
| Renderer (D3DMetal/DXVK) | x86-64 PE → Rosetta | **ARM64EC PE → native** |
| Game code | x86-64 PE → Rosetta | x86-64 PE → **FEX, in-layer** |

Work Cellar owns:

- [x] Runner architecture is a first-class, *measured* property — `RunnerArchitecture`
      (`x86_64` / `arm64ec`), `RunnerInstall.measuredArchitectures` via `lipo`, and a
      `Runner arch` check in `cellar doctor` that reports what is installed rather than assuming
- [ ] Catalog entry for the arm64ec runner (artifacts + `emulator: "FEX"`) once a free build exists
- [ ] Per-profile runner pinning, so a game can stay on the x86_64 runner while others move
- [ ] Bottle migration: ARM64EC prefixes are not convertible from x86-64 ones — `cellar prefix`
      needs a "recreate on the new runner, keep the game files" path
- [ ] Re-verify the whole matrix (Steam client, Battle.net, PC2, Diablo IV) on the native runner

Upstream gates, none of them ours (revisit each macOS/CrossOver release):

1. **A free prebuilt arm64 macOS Wine with the ARM64EC hook** — Gcenx, Sikarugir or WineForge
   packaging it. Wine has had ARM64EC support since 10.0 (Jan 2025); macOS packaging is the gap.
2. **FEX's macOS port** usable as that hook. CodeWeavers made a custom FEX work on macOS in July
   2026; FEX is MIT and CodeWeavers upstreams first, so this is likely but not yet done in public.
3. **An ARM64EC renderer.** Apple's D3DMetal 4 (GPTK 4 / Metal 4, Apple-Silicon-only, macOS 27) is
   the fast path if Apple ships ARM64EC DLLs; DXVK + VKD3D-Proton on MoltenVK rebuilt for arm64ec
   is the fully-free fallback that needs no Apple decision. Keeping that fallback working is why
   the DXVK path stays first-class.

Timing: CrossOver 27 (the commercial reference) is penciled in for early 2027. Cellar's own
deadline is macOS 28 in fall 2027, and staying on macOS 27 is a valid user-facing answer until
the native runner is real.

## Known risks tracked across phases

- **Rosetta sunset** — see Phase 6. General-purpose Rosetta is removed in macOS 28 (fall 2027);
  the retained gaming subset is a *partial mitigation, not a guarantee* for a Wine layer. macOS
  already shows an "Intel app support ending" notice for the x86_64 runner — harmless on macOS
  26/27. `cellar doctor` reports the measured runner architecture and the horizon.
- **Renderer lock-in** — D3DMetal is Apple's, proprietary, and only Apple can make it ARM64EC.
  The DXVK/VKD3D + MoltenVK path is the hedge and must keep working, even while it is slower.
- **GPTK license** — keep D3DMetal user-supplied; keep the DXVK/MoltenVK path fully functional.
- **Maintenance** — upstream fixes, community-owned profiles, small core (lessons from Whisky's end).
