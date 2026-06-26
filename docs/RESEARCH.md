# Research notes (2026)

The design decisions in Cellar are grounded in verified research (primary sources: license files,
Apple announcements, the Steam Subscriber Agreement, upstream repos). Key findings, condensed:

## Translation stack

- **Wine** (LGPL-2.1+) reimplements Win32 — not an emulator. It is the foundation; CrossOver is the
  commercial Wine whose source Apple licensed to build the Game Porting Toolkit.
- **D3DMetal** (Apple, proprietary) translates **DirectX 11/12 → Metal** directly (one hop) — the
  fastest path for modern games on Apple Silicon. **No DirectX 9.** Versions: 1.x (2023) → 3.0
  (CrossOver 26, Feb 2026). GPTK 4 / Metal 4 announced WWDC 2026, targeting macOS 27.
- **FOSS path:** DXVK (zlib, DX9/10/11 → Vulkan) + VKD3D-Proton (LGPL-2.1+, DX12 → Vulkan) +
  **MoltenVK** (Apache-2.0, Vulkan → Metal). Weaker on macOS because MoltenVK isn't fully Vulkan-
  conformant (macOS DXVK pinned to the old 1.10.x line); good for DX9/older and as a fallback.
- **Proton doesn't run on macOS:** it needs native Vulkan (macOS has only Metal) and the Linux Steam
  client's compatibility-tool hook (absent on macOS). GPTK/CrossOver is the closest equivalent.
- **Rosetta 2** translates x86-64 → ARM64 (AVX/AVX2 since macOS 15). **Sunset:** general-purpose
  Rosetta is removed in **macOS 28 (fall 2027)**; macOS 27 is the last full-Rosetta release. Apple
  keeps a **gaming-focused subset** afterward — a partial mitigation, not a guarantee.

## Tooling landscape

- **Whisky** (native SwiftUI, GPL-3.0) was **archived 11 May 2025** — maintainer cited burnout and a
  "parasitic" relationship with Wine/CrossOver. The polished native-app niche is now open.
- **Heroic** (Electron, GPL-3.0) is the maintained all-in-one but imports Epic/GOG/Amazon — **not
  Steam libraries**. **Sikarugir** (ex-Kegworks) carries the Wineskin lineage in Obj-C.
- **CrossOver 26** (Feb 2026, Wine 11 + D3DMetal 3.0) is the commercial benchmark and even runs some
  anti-cheat AAA titles. **Gcenx**'s Homebrew tap is the de-facto free distribution channel for
  prebuilt Wine + GPTK on macOS.

## Planet Coaster 2 (Steam AppID 2688950)

- Frontier **COBRA** engine, **DirectX 12**, x86-64, released 6 Nov 2024.
- **No kernel anti-cheat** (no EAC/BattlEye/Vanguard) — confirmed absent from GamingOnLinux's DB.
- Ships **Denuvo Anti-tamper** (DRM, *not* anti-cheat) + a Frontier account; needs a **live Steam
  session** (→ Windows-Steam-in-bottle is the robust install path). Denuvo runs untouched in the layer.
- Has substantial online co-op / async multiplayer / cross-platform saves (so "single-player only" is
  imprecise). Real Apple Silicon results historically **mixed**; CrossOver 26 lists it "enabled". No
  M5 benchmarks yet — Cellar's PC2 profile is marked `experimental` pending validation.

## Steam install block

- The macOS Steam client greys out **Install** for Windows-only games (no macOS depot) — metadata, not
  a bug, and not overridable in the normal Mac UI.
- Legitimate, ownership-gated ways to get the Windows files you own: **Windows Steam in a bottle**
  (default, robust, satisfies live-session DRM), **DepotDownloader** (GPL-2.0, `-os windows`), or
  **steamcmd** `+@sSteamCmdForcePlatformType windows`. See [LEGAL.md](LEGAL.md) for the honest framing.

## Selected sources

- Apple GPTK: <https://developer.apple.com/games/game-porting-toolkit/>
- CrossOver 26: <https://www.codeweavers.com/blog/mjohnson/2026/2/10/crossover-26-cures-artificial-incompatibility-with-windows-games-on-mac>
- Whisky archived / maintenance notice: <https://github.com/Whisky-App/Whisky> · <https://docs.getwhisky.app/maintenance-notice>
- MoltenVK: <https://github.com/KhronosGroup/MoltenVK> · DXVK: <https://github.com/doitsujin/dxvk> · VKD3D-Proton: <https://github.com/HansKristian-Work/vkd3d-proton>
- PC2 DRM / store page: <https://store.steampowered.com/app/2688950/Planet_Coaster_2/> · anti-cheat DB: <https://www.gamingonlinux.com/anticheat/>
- DepotDownloader: <https://github.com/SteamRE/DepotDownloader> · SteamCMD: <https://developer.valvesoftware.com/wiki/SteamCMD>
- Steam Subscriber Agreement: <https://store.steampowered.com/subscriber_agreement/>
- Rosetta sunset: <https://www.macrumors.com/2025/06/10/apple-to-phase-out-rosetta-2/>
