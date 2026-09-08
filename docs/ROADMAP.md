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

- ✅ **The library is gated on signing in, and shows only games you own.** Cellar lists your games,
  not its catalogue: a store's section appears once it is connected, and holds only what the store
  confirms you own. GOG answers exactly; Steam answers exactly once it can be asked (a Web API key —
  `cellar steam key` — or a public profile) and otherwise confirms only what is installed and says
  so; Battle.net can never answer, so connecting it is the player's word and its games are shown
  unverified rather than hidden forever. `cellar library`, and the app's first-run sign-in screen.
  Rule and cache live in `StoreLibrary` / `LibraryAccess`, checked in `cellar selftest`.

Next in this direction, not yet done:

- Browse the full owned library rather than curated profiles. Cellar now *reads* the owned library
  for Steam and GOG to decide what to show; the remaining step is offering a game it has no profile
  for. Steam and Battle.net still need a profile to *run* a game.
- Epic Games Store: a genuine OAuth flow (as Legendary/Heroic use), but reverse-engineered against the
  launcher's own client credentials — a bigger surface and a bigger judgement call than GOG's.
- Generate a profile from a store's metadata, so adding a game is not hand-writing TOML.

## Known risks tracked across phases

- **Rosetta sunset** — general-purpose Rosetta is removed in macOS 28 (fall 2027); Apple keeps a
  gaming-focused subset (which this GPTK/Wine use case falls under). macOS already shows an "Intel app
  support ending" notice for the x86_64 GPTK runner — harmless on macOS 26/27. `cellar doctor`
  surfaces the timeline. **Migration target:** add a native **ARM64EC Wine** runner (Wine 10+ ARM64EC,
  native-ARM CrossOver preview, GPTK 4 / Metal 4) as it matures into a free build; the x86_64 game
  code still runs via the retained Rosetta/ARM64EC x86 emulation regardless.
- **GPTK license** — keep D3DMetal user-supplied; keep the DXVK/MoltenVK path fully functional.
- **Maintenance** — upstream fixes, community-owned profiles, small core (lessons from Whisky's end).
