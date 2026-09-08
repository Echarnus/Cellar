# Cellar

**A free, open, Proton-like layer for running Windows games on macOS (Apple Silicon).**

Cellar assembles a [Wine](https://www.winehq.org/) runner plus a graphics-translation backend
(Apple's **D3DMetal**, or the open-source **DXVK → MoltenVK** path) into per-game **bottles**,
driven by a community **profile database**. Each game names the **storefront** it came from, and
Cellar stands that client up inside the bottle — Windows **Steam**, or Blizzard's **Battle.net**.
The engine is general: adding a game means adding a profile, not rebuilding the layer.

> **Status:** Phase 1 (working). **Planet Coaster 2 is playable on an Apple M5 / macOS 26.5** —
> `cellar setup` installs the runner (WineForge: Wine 11.17 + D3DMetal 3.0), creates the bottle,
> installs Windows Steam and a `Steam (<bottle>).app`; you log in, install PC2, and `cellar launch`
> it. Menu ~55 FPS, in-park renders (a huge park is CPU-bound via Rosetta). PC2 needs Metal's
> validation layer on as a stability workaround for a D3DMetal startup race — set in its profile.
> See [docs/ROADMAP.md](docs/ROADMAP.md) and [docs/RESEARCH.md](docs/RESEARCH.md).

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

## Two storefronts, told apart properly

A profile says `store = "steam"`, `"battlenet"` or `"standalone"`, and that decides everything
downstream — which client `cellar setup` installs, what "installed" means, how a launch is issued,
and what the app tells you. The differences are real, and Cellar refuses to paper over them:

| | Steam | Battle.net |
|---|---|---|
| Installing the client | silent (`/S`) | **not silent** — Blizzard's window opens and wants a few clicks, so Cellar warns you before it does |
| Who's signed in | readable (`loginusers.vdf`) — the app shows your account | **not published** — so Cellar shows no sign-in step and no false ✗; you sign in inside the client |
| Games are named by | AppID (`2688950`) | product code (`Fen` = Diablo IV) |
| Installing a game | `cellar steam install <slug>` | opens Battle.net — Blizzard exposes no install URL a launcher can drive |
| Launching | `steam://rungameid/…` into a silent client | `Battle.net.exe --exec="launch Fen"`, client warmed first |

```sh
# Diablo IV, via Battle.net
cellar setup --profile diablo-4     # runner + bottle + Battle.net (its installer needs a few clicks)
cellar battlenet open diablo-4      # sign in, install the game from the client
cellar launch diablo-4              # play — quitting the game closes the whole layer
```

In the app the library is grouped by store, each game carries its storefront's mark and name, and
the detail page states what the profile actually knows: developer, engine, graphics API, anti-cheat,
DRM, and an honest `status` — including "untested" when that's the truth.

---

## Free and legal by design

Cellar is **GPL-3.0** and is built to **stay** free and legal:

- **Cellar never bundles Apple's D3DMetal in its own releases.** D3DMetal is proprietary, but Apple's
  license permits non-commercial *distribution*. So it reaches your machine at runtime, grafted from
  the community WineForge / Sikarugir builds under Apple's non-commercial grant (the same model
  Heroic uses) — never part of Cellar's source or artifacts.
- **No DRM circumvention, ever.** Planet Coaster 2 ships **Denuvo Anti-tamper** (DRM, *not*
  anti-cheat). Cellar runs it **through** the layer, untouched. We never strip or crack DRM.
- **Owned games only.** Any game files come from *your* authenticated account, through that
  storefront's own client running unmodified in the bottle.
- **Trademark-safe.** Cellar is not affiliated with or endorsed by Apple, Valve, Blizzard,
  CodeWeavers, or Frontier Developments. The store marks in the app are drawn by Cellar's own code —
  no logo files are bundled or fetched. See [NOTICE](NOTICE).

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

## Usage

The minimal-setup path to Planet Coaster 2:

```sh
cellar doctor                       # check your machine (Apple Silicon, Rosetta, disk…)
cellar setup                        # install runner + bottle + Windows Steam (Planet Coaster 2)
cellar steam open  planet-coaster-2 # opens Steam in the bottle — log in (Steam Guard/2FA works)
cellar steam install planet-coaster-2  # opens the install dialog for PC2 (or install from the UI)
cellar launch      planet-coaster-2 # play (routes through Steam so DRM/auth work)
```

Surface it like a native game:

```sh
cellar steam add planet-coaster-2   # generates ~/Applications/Planet Coaster 2.app
                                    # and a non-Steam shortcut (quit Steam first)
```

Other commands: `cellar runner list/install`, `cellar prefix list`, `cellar profiles list/show`,
`cellar steam enable-windows-platform` (advanced).

---

## Contributing

New games are added as **profiles** — see [CONTRIBUTING.md](CONTRIBUTING.md). Cellar's policy is to
**upstream fixes** to Wine/DXVK where possible (one of the lessons from Whisky's end), keep the core
small, and let the community own the profile database.

## License

[GPL-3.0](LICENSE) © Cellar contributors. Bundled third-party components retain their own licenses
([THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)).
