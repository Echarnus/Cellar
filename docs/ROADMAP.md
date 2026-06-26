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

## Phase 1 — Single-game PC2 runner (MVP)

- [ ] `cellar runner install <id>` — download/pin a prebuilt LGPL Wine 11 (Gcenx wine-crossover)
- [ ] Initialize the Wine prefix (`wineboot`) inside a bottle
- [ ] `cellar gptk import <dmg>` — mount Apple's GPTK `.dmg`, copy D3DMetal into the local cache
- [ ] Backend wiring: D3DMetal + DLL overrides; DXVK fallback as a switch
- [ ] `cellar install-steam <prefix>` — install the Windows Steam client into the bottle
- [ ] `cellar launch planet-coaster-2` — run through bottle + backend + Rosetta
- [ ] Test target (`swift test`)
- [ ] **Verify:** install PC2 via in-bottle Steam and boot it on M5 / macOS 26; record a perf note

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
  gaming-focused subset. Plan for native-ARM Wine builds; warn at runtime on macOS 28+.
- **GPTK license** — keep D3DMetal user-supplied; keep the DXVK/MoltenVK path fully functional.
- **Maintenance** — upstream fixes, community-owned profiles, small core (lessons from Whisky's end).
