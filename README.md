# Cellar

**A free, open, Proton-like layer for running Windows games on macOS (Apple Silicon).**

Cellar assembles a [Wine](https://www.winehq.org/) runner plus a graphics-translation backend
(Apple's **D3DMetal**, or the open-source **DXVK → MoltenVK** path) into per-game **bottles**,
driven by a community **profile database**. The first supported profile is **Planet Coaster 2**;
the engine itself is general — adding a new game means adding a profile, not rebuilding the layer.

> **Status:** Phase 0 (bootstrap). The `doctor`, `prefix`, and `profiles` commands work today.
> Runner download, GPTK import, Steam-in-bottle install, and launch land in Phase 1.
> See [docs/ROADMAP.md](docs/ROADMAP.md).

---

## Why this exists (and how it differs from Proton)

Valve's **Proton** runs Windows games on **Linux** — and it relies on two things macOS doesn't have:

1. **Native Vulkan.** Proton translates DirectX → Vulkan (via DXVK / VKD3D-Proton) and runs on
   Linux's native Vulkan driver. macOS has **no Vulkan** — only Metal. So the Mac equivalent is
   **Wine + Apple's D3DMetal** (DirectX → Metal directly), with the open-source
   **DXVK → MoltenVK** chain as a fallback.
2. **Steam Play.** On Linux, the Steam client hosts compatibility tools so you select Proton in a
   game's properties and click Play. **The macOS Steam client has no such hook** — it's Linux-only.

So Cellar can't *be* Proton hosted inside Steam. Instead it **owns the launch path** — the same role
Steam-on-Linux plays — and gets you the same feel:

- **Windows Steam in a bottle** — install the real Windows Steam client inside the bottle and let it
  install/validate/update your games. This is also the clean answer to *"the Mac Steam client won't
  let me install this Windows-only game"* (it greys out the Install button because there's no macOS
  build). Inside the bottle, Steam sees Windows and just works.
- **Per-game profiles** — Cellar's equivalent of Proton's per-title fixes: backend choice, Wine
  build, registry tweaks, env vars, install recipe — set once, reused forever.
- *(planned)* **Send to Steam** — generate a launcher and a non-Steam shortcut so a title appears in
  your Steam library with a Play button.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full stack.

---

## Free and legal by design

Cellar is **GPL-3.0** and is built to **stay** free and legal:

- **Apple's D3DMetal is never bundled.** It's proprietary (Apple's license permits personal /
  non-commercial use only). You download Apple's Game Porting Toolkit `.dmg` yourself and run
  `cellar gptk import` — Cellar copies it into your local cache and never redistributes it.
- **No DRM circumvention, ever.** Planet Coaster 2 ships **Denuvo Anti-tamper** (DRM, *not*
  anti-cheat). Cellar runs it **through** the layer, untouched. We never strip or crack DRM.
- **Owned games only.** Any game files come from *your* authenticated account.
- **Trademark-safe.** Cellar is not affiliated with or endorsed by Apple, Valve, CodeWeavers, or
  Frontier Developments. See [NOTICE](NOTICE).

Full component-by-component license matrix: [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
Detailed rules: [docs/LEGAL.md](docs/LEGAL.md).

---

## Requirements

- **Apple Silicon** Mac (M1 or newer; developed/tested on **M5**)
- **macOS 14 (Sonoma)** or later — recommended **macOS 26 (Tahoe)**
- **Rosetta 2** (`softwareupdate --install-rosetta --agree-to-license`)
- **Swift 6** toolchain (Xcode or Command Line Tools) to build from source

## Build & run

```sh
git clone https://github.com/<you>/Cellar.git
cd Cellar
swift build
swift run cellar doctor      # check your machine is ready
```

Install the binary onto your PATH:

```sh
swift build -c release
cp .build/release/cellar /usr/local/bin/cellar
cellar doctor
```

## Usage (Phase 0)

```sh
cellar doctor                          # environment diagnostics
cellar profiles list                   # list available game profiles
cellar profiles show planet-coaster-2  # inspect the PC2 profile
cellar prefix create pc2 --backend d3dmetal
cellar prefix list
```

Coming in Phase 1: `cellar runner install`, `cellar gptk import`, `cellar install-steam`,
`cellar launch planet-coaster-2`.

---

## Contributing

New games are added as **profiles** — see [CONTRIBUTING.md](CONTRIBUTING.md). Cellar's policy is to
**upstream fixes** to Wine/DXVK where possible (one of the lessons from Whisky's end), keep the core
small, and let the community own the profile database.

## License

[GPL-3.0](LICENSE) © Cellar contributors. Bundled third-party components retain their own licenses
([THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)).
