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

## Update 2026-09-07 — Planet Coaster 2 running on M5, and the runner that does it

Validated on an Apple M5 / macOS 26.5. The runner choice turned out to be the whole problem:

- **Apple GPTK (Wine 7.7)** cannot run the *current* Windows Steam client: its Chromium web helper
  (`steamwebhelper`, CEF 126) asserts `Check failed: NOTREACHED` and crash-loops. No launch flag
  fixes it. GPTK is now marked deprecated in Cellar.
- **Sikarugir Wine 10.0** runs Steam and installs PC2, but PC2 access-violates ~5 s in. The fault is
  an inlined `GetCurrentFiber()` compiled to `mov rax, gs:[0x20]`. macOS Wine **before 10.8** keeps
  its own pthread block in the GS base, so the game reads a Mach port as a fiber pointer. (Wine 10.8+
  switches the GS base to the real TEB inside PE code — confirmed by the presence of
  `_thread_set_tsd_base` in `dlls/ntdll/unix/signal_x86_64.c` from 10.8 on.)
- **Stock Wine 11** fixes the fiber issue but removed the `ntdll.__wine_unix_call` export that
  D3DMetal's DLLs import → `unimplemented function, aborting`.
- **WineForge 0.6.0.4** (Wine 11.17 + CodeWeavers' macOS patch set) satisfies both. Cellar grafts
  the Sikarugir template's `renderer/d3dmetal` into `<runner>/wine/lib/d3dmetal` and selects it with
  `GRAPHICS_BACKEND=d3dmetal` + `D3DMETAL_RUNTIME_DIR`. This is Cellar's **default** runner.

Other load-bearing facts learned:

- **Do not launch Wine through `/usr/bin/arch -x86_64`.** SIP strips `DYLD_*` from system binaries,
  so the runner's own dylibs (wineserver's `@rpath/libinotify`, D3DMetal) fail to load. Run the
  x86_64-only Mach-O directly; Rosetta handles it.
- **Inherit the caller's environment.** A bare environment makes PC2 exit silently ~4 s in.
- **Steam bootstrap pin** (`steam.cfg` `BootStrapperInhibitAll`) must be written *after* the first
  self-update; before it, the bootstrapper has no client and exits in 2 s.
- The `-allosarches -cef-force-32bit …` launch-flag folklore is a no-op. Cellar passes no flags.

**PC2 stability:** even on WineForge, PC2 fast-fails `0xC0000409` on some launches — a race in
D3DMetal 3.0's ray-tracing `D3D12AccelerationStructure` builder (symbolicated from the framework).
Running with Metal's API validation layer on (`MTL_DEBUG_LAYER=1`) shifts the timing so it usually
gets past startup and then runs for minutes. Documented as a workaround (CrossOver 26's changelog
lists PC2 among its fixes, so a newer D3DMetal likely resolves it).

**PC2 performance:** menu 54-57 FPS; a 283k-guest showcase park ~22 FPS. Render-scale 0.7 cut GPU
time 34→26 ms with no FPS change → CPU-bound (Rosetta translating ~26,800 draw submissions/frame).
Graphics settings barely help the heavy park; fewer objects do. Ordinary parks and the menu are
smooth.

## Age of Empires II: Definitive Edition (AppID 813780)

Has a **native Apple Silicon port by Feral Interactive** on Steam since 2026-05-28 — install it from
the macOS Steam client directly, no Cellar needed. A Cellar profile exists for the Windows build
(DX11 via D3DMetal); EasyAntiCheat is enforced only for ranked multiplayer, which is unsupported
through the layer.
