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
  Rosetta is removed in **macOS 28 (fall 2027)**; macOS 27 ("Golden Gate", Apple-Silicon-only) is
  the last full-Rosetta release. Apple keeps a **gaming-focused subset** afterward, scoped to
  "older unmaintained gaming titles that rely on Intel-based frameworks" — a partial mitigation,
  not a guarantee, and never confirmed to cover a Wine layer.
- **ARM64EC + FEX is the post-Rosetta architecture.** Wine has had full **ARM64EC** support since
  **10.0** (Jan 2025): Wine's own PE DLLs are native ARM while x86-64 app code goes through a
  pluggable emulator. **FEX** (MIT) is that emulator. CodeWeavers integrated FEX for Linux ARM64
  in Nov 2025 and shipped the **first Mac ARM64 CrossOver preview in July 2026** — no D3DMetal and
  no D3D12 in that build yet, no bottle conversion, many launchers broken; **CrossOver 27** (early
  2027) is the target for a usable version. Both halves being free software is what makes this
  reachable for Cellar — see [ROADMAP.md](ROADMAP.md) Phase 4.
- **D3DMetal 4 / GPTK 4** (WWDC 2026, macOS 27) drops Intel Macs and targets **Metal 4**
  (neural rendering, MetalFX frame interpolation), faster than GPTK 3 at DX12. Whether Apple ships
  **ARM64EC** D3DMetal DLLs is the open question that decides if the native path keeps the fast
  renderer or falls back to DXVK/VKD3D on MoltenVK.

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
- Rosetta sunset: <https://www.macrumors.com/2025/06/10/apple-to-phase-out-rosetta-2/> ·
  Apple's notice: <https://support.apple.com/en-gb/102527>
- CrossOver Mac ARM64 preview (Jul 2026):
  <https://www.codeweavers.com/blog/mjohnson/2026/7/31/crossover-preview-the-right-to-bear-arm64-on-mac> ·
  <https://appleinsider.com/articles/26/07/31/first-apple-silicon-native-crossover-build-in-testing-as-rosettas-end-nears>
- CodeWeavers PortJump / Intel-app support changes:
  <https://www.codeweavers.com/blog/orudge/2026/6/19/portjump-update-upcoming-changes-to-macos-support-for-intel-based-applications>
- FEX-Emu (MIT): <https://github.com/FEX-Emu/FEX> · ARM64EC notes:
  <https://wiki.fex-emu.com/index.php/Development:ARM64EC>
- GPTK 4 / Metal 4: <https://appleinsider.com/articles/26/06/17/apples-game-porting-toolkit-4-is-a-big-improvement-for-modern-game-coders>

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

## Update 2026-09-08 — Battle.net as a second store, and Diablo IV

Cellar's first non-Steam storefront. Everything below is sourced; nothing here has yet been run on
Kenneth's M5, and `profiles/diablo-4.toml` says `status = "untested"` for that reason.

### The client

| Fact | Value | Where it came from |
|---|---|---|
| Installer | `https://www.battle.net/download/getInstallerForGame?os=win&version=LIVE&gameProgram=BATTLENET_APP` | Lutris' *Battle.net (Standard)* installer script |
| Install flags | `--lang=enUS --installpath="C:\Program Files (x86)\Battle.net"` | SilentInstallHQ's Battle.net guide |
| **Silent install** | **Does not exist.** Those flags only pre-fill the dialog; the UI still appears. A Blizzard forum request for a `/quiet` switch is unanswered. | SilentInstallHQ; Blizzard forums; Lutris' own step is captioned *"an installer will open"* |
| Two executables | `Battle.net Launcher.exe` bootstraps and updates; `Battle.net.exe` is the client and the only one that takes `--exec` | Lutris docs (`Battle.Net.md`) |
| Stray processes | `Battle.net.exe`, `Agent.exe`, `Battle.net Helper.exe` outlive the client; a surviving `Agent.exe` is what greys out the Install button next session | Lutris docs; Lutris' `exclude_processes` list |
| Config | `drive_c/users/<user>/AppData/Roaming/Battle.net/Battle.net.config`, JSON, values are **strings** not booleans | Lutris `write_json` step |

### The config that makes it work under Wine

```json
{ "Client": { "GameLaunchWindowBehavior": "2" },
  "GameSearch": { "BackgroundSearch": "true" },
  "HardwareAcceleration": "false",
  "Sound": { "Enabled": "false" },
  "Streaming": { "StreamingEnabled": "false" } }
```

`HardwareAcceleration: false` is the load-bearing one. The client draws its UI in an embedded
Chromium; GPU-accelerated under Wine that renders as a spinning logo with no login form, or a white
window. `StreamingEnabled: false` fixes games black-screening on launch. Cellar writes this during
setup rather than waiting for the player to hit the bug — `cellar battlenet configure` re-applies it,
since the client rewrites its own config on exit.

### Launching a game

`Battle.net.exe --exec="launch <product>"`, where the product code is Blizzard's internal name —
**Diablo IV is `Fen`** (from its "Fenris" codename). The catch, reported consistently: `--exec` is
dropped when no client is already running. So Cellar starts the launcher, waits for `Battle.net.exe`
to appear, lets it settle, and only then issues the launch — then supervises the startup with the
same retry loop the Steam path uses (`ProcessWatch.superviseStart`).

### Diablo IV specifics

- **No kernel anti-cheat.** It runs under Proton on Steam Deck (ProtonDB: Gold) and under CrossOver on
  macOS, neither of which a ring-0 driver would allow. Blizzard's protection is user-space.
- **Always-online**, even solo — there is no store-free launch path; the client stays up alongside it.
- **D3DMetal works, with a fast sync on.** CrossOver's Diablo IV guidance is explicit that MSync
  must be enabled with D3DMetal. `WineRunner` sets the fast sync the runner actually implements —
  found 2026-09-09: WineForge has no msync at all (`WINEMSYNC=1` was a no-op there), its equivalent
  is **WFUSync** (`WINEWFUSYNC=1`), which Cellar now reads from the runner's `ntdll.so` and sets.
- **Patch days are turbulent.** A launch crash was reported on CrossOver 26.2 / macOS 26.5.2 after
  Season 14 (patch 3.1.0, 2026-06-30). Recorded in the profile's `notes` rather than glossed over.
- **Artwork.** Battle.net publishes none addressable by product code. Diablo IV is also sold on Steam
  (AppID 2344520) and Valve's CDN serves that key art publicly, so the profile points `art_portrait` /
  `art_hero` there. Installation and launch still go through Battle.net; only the pictures come from
  Steam.
- **Prior art:** [D4Mac](https://github.com/MichaelLod/D4Mac) — an open-source Battle.net launcher for
  Apple Silicon (Wine 11 from CrossOver 26.1 + GPTK 3.0, DXMT for the client's 32-bit D3D11, MoltenVK
  fallback). It corroborates the stack and recommends `WINEESYNC=1` + `ROSETTA_ADVERTISE_AVX=1` for
  the Rosetta-deadlock freezes that macOS 26.5 fixed.

### Sources

- Lutris — Battle.net (Standard) installer script, and `lutris/docs/Battle.Net.md`
- Lutris — Diablo IV (Battle.net) installer script (`--exec="launch Fen"`, `locationapi=d`)
- SilentInstallHQ — *Battle.net Silent Install (How-To Guide)*
- CodeWeavers — Diablo IV compatibility forum (D3DMetal + MSync; the Season 14 crash report)
- ProtonDB / ValveSoftware/Proton #7199 — Diablo IV anti-cheat and Linux status
- MichaelLod/D4Mac — Battle.net on Apple Silicon, prior art

