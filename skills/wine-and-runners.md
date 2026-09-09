# Skill: Wine, runners, backends & bottles

Cellar's core competency. Best practices for `Runner.swift`, `Wine.swift`, `Prefix.swift` and
anything that assembles or launches the translation layer. Portable guide; Claude's auto-discovered
copy is `.claude/skills/cellar-wine/SKILL.md`.

Read [`../AGENTS.md`](../AGENTS.md) first. The *evidence* behind everything below — versions, dates,
symbolicated crashes, sources — lives in [`../docs/RESEARCH.md`](../docs/RESEARCH.md); the stack
diagram is in [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md). **This file is the rules; those
are the receipts.** Don't restate a finding here without a source there.

## The stack, in one breath

Windows `.exe` (x86-64, DirectX) → **Wine** (Win32 → macOS, *not* an emulator) → a **graphics
backend** (Apple **D3DMetal** DX11/12 → Metal in one hop, or **DXVK**/**VKD3D-Proton** → Vulkan →
**MoltenVK** → Metal) → **Rosetta 2** (x86-64 → ARM64) → Apple Silicon.

Backend is **per profile**, not global: `d3dmetal | dxvk | vkd3d | wined3d | dxmt`, with a
`fallback_backend`. D3DMetal is fastest for modern titles but is **proprietary and has no DX9**;
the DXVK path is fully open source and is the right answer for DX9/older titles and as a fallback.

## Rules that are not negotiable

- **Never bundle D3DMetal.** It is Apple's, user-supplied, grafted at runtime from a community runner
  or `cellar gptk import` into `~/Library/Application Support/Cellar/cache/d3dmetal`. It must never
  appear in the repo or in a release artifact. This is a licence boundary, not a preference.
- **Never circumvent DRM or anti-cheat.** Denuvo, Battle.net's always-online check and friends run
  *through* the layer, untouched. A profile that needs a live session says so and Cellar stands the
  real client up — it does not work around it.
- **Never commit bottles, runners, depots or logs.** The ignore rules cover `/runners/`,
  `/prefixes/`, `/cache/` and `/logs/`; keep it that way.

## Launching Wine — the four findings that cost the most to learn

These are empirical, validated on an M5 / macOS 26.5, and every one of them looks like a
micro-optimisation until you remove it:

1. **Do not launch Wine through `/usr/bin/arch -x86_64`.** SIP strips `DYLD_*` from system binaries,
   so the runner's own dylibs (wineserver's `@rpath/libinotify`, D3DMetal's unix halves) fail to
   resolve. The x86_64-only Mach-O runs under Rosetta perfectly well on its own — invoke it directly.
2. **Inherit the caller's environment, then overlay.** A *bare* environment makes Planet Coaster 2
   exit silently ~4 s after launch. `WineRunner.environment` starts from
   `ProcessInfo.processInfo.environment` (keeping `TMPDIR`, `USER`, `LANG`,
   `__CF_USER_TEXT_ENCODING`) — the same approach Proton takes.
3. **…but strip the caller's Wine/graphics variables first.** Any inherited `WINE*`, `DYLD_*`,
   `D3DM*`, `MTL_*`, `DXMT_*`, `GST_*` or `GRAPHICS_BACKEND` is another runner's settings leaking in.
   `environment()` deletes them before setting Cellar's own. If you add a new variable family, add it
   to that strip list too.
4. **Merge `WINEDLLOVERRIDES`, never assign over it.** The backend sets its own overrides, the Steam
   overlay disable (`gameoverlayrenderer64=d`) is appended, and a profile's `[env]` override is
   merged with `;`. A plain assignment silently drops the backend's DLL selection and the game
   launches on the wrong renderer — which presents as a mystery crash, not a configuration error.

## Sync primitives

**Every macOS Wine build brings its own fast sync, switched on by its own variable, and ignores the
others.** Sikarugir (Wine 10) implements msync + esync (`WINEMSYNC`, `WINEESYNC`); WineForge
(Wine 11) implements neither and ships **WFUSync** (`WINEWFUSYNC`, on `os_sync_wait_on_address`).
For months Cellar set `WINEMSYNC=1` everywhere — right for Sikarugir, a no-op on the default runner,
which therefore ran every game through wineserver. So the variables are not a constant: `FastSync`
scans the runner's `ntdll.so` for the names it recognises and `WineRunner` sets exactly those
(all three when the file cannot be read — an unknown variable costs nothing, a missing one costs
the fast path). `cellar doctor` prints the result per runner as *Fast sync*. Check that line
before believing any sync setting; verify a new runner by `strings` on its `ntdll.so`, not by
its README. CrossOver's Diablo IV guidance that msync must be on with D3DMetal still stands for
builds that have it; a profile's `[env]` can force a variable either way (`WINEWFUSYNC = "0"`).

## MetalFX

`metalfx_upscaling = true` in a profile's `[graphics]` presents the **NVIDIA identity** (WineForge's
documented block: `D3DMETAL_UPSCALER_PROFILE=nvidia`, `D3DM_ENABLE_METALFX=1`, `nvapi,nvapi64,nvngx=b`)
so the game's DLSS option becomes MetalFX. `WineRunner.usesMetalFX` honours it only on D3DMetal and
only when the grafted runtime ships `nvngx.dll` + `nvapi64.dll` (`RunnerInstall.hasMetalFXShim`);
otherwise the launch keeps the AMD/FidelityFX identity, and `cellar doctor` says whether the shims
are there. It is a GPU-side lever — it does nothing for a CPU-bound (Rosetta-bound) scene.

## Choosing a runner (why WineForge, and why not the others)

The runner *is* the compatibility story. The current default is **WineForge** (Wine 11.17 +
CodeWeavers' macOS patch set) carrying **D3DMetal 3.0**. Each rejected option was rejected for a
specific, reproducible reason:

| Runner | Why not |
|---|---|
| Apple **GPTK** (Wine 7.7) | The current Windows Steam client's Chromium helper (`steamwebhelper`, CEF 126) asserts `NOTREACHED` and crash-loops. No launch flag fixes it. Marked deprecated in Cellar. |
| **Sikarugir** Wine 10.0 | Steam works, but a game inlining `GetCurrentFiber()` as `mov rax, gs:[0x20]` reads a Mach port instead of the fiber on macOS Wine **< 10.8** → access violation seconds in. |
| Stock **Wine 11** | Fibers fixed, but it removed the `ntdll.__wine_unix_call` export that D3DMetal's DLLs import → *unimplemented function, aborting*. |
| **WineForge 0.6.0.4** | Both fixed. **This is the default.** |

Two shapes of runner exist in `RunnerInstall`, and `WineRunner.environment` branches on them:

- **WineForge-style** — backend chosen by `GRAPHICS_BACKEND` + `D3DMETAL_RUNTIME_DIR` /
  `DXMT_RUNTIME_DIR`, DLLs forced native via `WINEDLLOVERRIDES`.
- **Wrapper/Frameworks-style** (Sikarugir lineage) — backend chosen by pointing
  `WINEDLLPATH_PREPEND` at the renderer directory, with `DYLD_FALLBACK_LIBRARY_PATH` letting the
  unix halves find `D3DMetal.framework` / MoltenVK. MoltenVK defaults
  (`MVK_CONFIG_RESUME_LOST_DEVICE=1`) belong to this path.

Adding a runner means teaching `RunnerInstall` its layout — **not** adding a branch at a call site.

## Bottles (prefixes)

One bottle per game: `~/Library/Application Support/Cellar/prefixes/<name>/` containing `pfx/` (the
actual `WINEPREFIX`) and a `bottle.toml` recording `backend`, `runner` and `windows_version`.

- **One game, one bottle.** Shared prefixes are how you get a DLL override for one title breaking
  another. Isolation is the entire point of the design.
- **Prefixes are not forward compatible.** A newer Wine silently upgrades a prefix on first run, and
  it may then be unusable with the older Wine. Changing a bottle's runner is therefore a real
  migration, not a config edit — recreate rather than swap in place.
- `bottle.toml` is read by a **tiny scalar scanner** (`PrefixManager.readBottleConfig`), not a TOML
  library: top-level `key = "value"` only, section headers ignored. Same constraints as a profile —
  see [`profiles.md`](profiles.md) before adding a field.
- **Tear the whole layer down with the game.** On exit Cellar kills the store client, its helpers
  (`Agent.exe`, `Battle.net Helper.exe` — a surviving `Agent.exe` greys out Install next session),
  then `wineserver -k`. A bottle that keeps a wineserver alive looks to the player like Cellar hung.

## Store clients live inside the bottle

A game needs the client it was bought from, running in the same bottle. That is the store layer's
job, not Wine's — `Store.swift` + `Steam.swift` / `BattleNet.swift`, keyed off the profile's `store`
field. The differences that bite (silent install, observable sign-in, how a launch is issued) are
tabulated in [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) → *The store layer*, and their UI
consequences are non-negotiable — see [`ux.md`](ux.md).

Two Wine-adjacent specifics worth keeping in mind here:

- **Steam bootstrap pin.** `steam.cfg`'s `BootStrapperInhibitAll` must be written *after* the first
  self-update; written before, the bootstrapper has no client and exits in ~2 s.
- **Battle.net renders its UI in embedded Chromium.** `HardwareAcceleration: "false"` in
  `Battle.net.config` is load-bearing — with GPU acceleration under Wine you get a spinning logo and
  no login form. The client rewrites its own config on exit, so re-applying it is a command
  (`cellar battlenet configure`), not a one-time setup step.

## Diagnosing a game that won't start

Work down the layer, not across the internet:

1. **Which runner and backend actually ran?** `bottle.toml` plus the env Cellar built
   (`cellar launch --print-env`). Most "it broke" reports are the wrong backend.
2. **Did Wine start at all,** or did it fail to load its own dylibs? A dyld error means rule 1 or 3
   above was violated.
3. **Is it the known D3DMetal race?** A fast `0xC0000409` at startup is the D3DMetal 3.0
   ray-tracing `D3D12AccelerationStructure` builder. `MTL_DEBUG_LAYER=1` shifts the timing enough to
   get past it — a documented workaround, recorded in the profile's `[env]`, not a fix.
4. **Only then** turn `WINEDEBUG` up — and remember that Wine's stderr is exactly the volume that
   deadlocks `Shell.run`; use `inheritIO` (see [`swift.md`](swift.md)).

Launch-flag folklore (`-allosarches`, `-cef-force-32bit`) has been tested and is a **no-op**. Don't
reintroduce it.

## The horizon: Rosetta's sunset

General-purpose Rosetta 2 is removed in **macOS 28 (fall 2027)**; macOS 27 is the last full-Rosetta
release, and Apple's remaining gaming-focused subset has never been confirmed to cover a Wine layer.
The post-Rosetta architecture is **ARM64EC** (Wine's own PE DLLs native ARM, x86-64 app code through
a pluggable emulator) + **FEX**. Both halves are free software, which is what makes it reachable.

Practical consequence for code you write today: **don't hard-code the assumption that the runner is
x86-64.** Anything that detects, reports or branches on runner architecture should read it rather
than assume it — `cellar doctor` already surfaces the horizon. Roadmap Phase 4 in
[`../docs/ROADMAP.md`](../docs/ROADMAP.md) owns the migration.

## Verify

A runner/backend/bottle change is verified by **a game actually starting**, never by a clean build:

1. `env -u DEVELOPER_DIR -u SDKROOT swift build -c release`, then `swift run cellar doctor`.
2. `cellar launch <slug> --print-env` — the env is the one you intended (right backend, overrides
   merged not clobbered, no leaked `WINE*` from your shell).
3. Launch the game, let it run past its startup race, and quit it — then confirm the teardown left no
   `wineserver`, `Agent.exe` or client process behind (`pgrep -fl wine`).
4. Record what you ran it on. A claim about compatibility without hardware and an OS version attached
   is not a fact — the profile's `notes` field exists for exactly this ([`profiles.md`](profiles.md)).

Related: [`profiles.md`](profiles.md) · [`swift.md`](swift.md) · [`ux.md`](ux.md) ·
[`../docs/RESEARCH.md`](../docs/RESEARCH.md) · [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md)
