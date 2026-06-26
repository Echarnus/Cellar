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
| Runner | (Phase 1) | download/pin prebuilt LGPL Wine 11; assemble backend DLL overrides |
| GPTK import | (Phase 1) | copy user-supplied D3DMetal from Apple's `.dmg` into the local cache |
| Steam-in-bottle | (Phase 1) | install the Windows Steam client into a bottle |
| Profile DB | `profiles/` + (Phase 2) loader/registry sync | per-game config, generality |
| GUI | (Phase 3) | native SwiftUI app over the same `CellarKit` core |

## On-disk layout

```
~/Library/Application Support/Cellar/
├── runners/     # installed Wine builds
├── prefixes/    # one bottle per game (pfx/ + bottle.toml)
├── cache/
│   └── d3dmetal/  # user-supplied Apple D3DMetal (never in the repo)
├── profiles/    # user/registry-synced profiles
└── logs/
```

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
