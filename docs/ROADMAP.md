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
- [ ] **Validate PC2 itself** on M5 / macOS 26 (log in, download, play) and record a perf/known-issues note
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

## Known risks tracked across phases

- **Rosetta sunset** — general-purpose Rosetta is removed in macOS 28 (fall 2027); Apple keeps a
  gaming-focused subset (which this GPTK/Wine use case falls under). macOS already shows an "Intel app
  support ending" notice for the x86_64 GPTK runner — harmless on macOS 26/27. `cellar doctor`
  surfaces the timeline. **Migration target:** add a native **ARM64EC Wine** runner (Wine 10+ ARM64EC,
  native-ARM CrossOver preview, GPTK 4 / Metal 4) as it matures into a free build; the x86_64 game
  code still runs via the retained Rosetta/ARM64EC x86 emulation regardless.
- **GPTK license** — keep D3DMetal user-supplied; keep the DXVK/MoltenVK path fully functional.
- **Maintenance** — upstream fixes, community-owned profiles, small core (lessons from Whisky's end).
