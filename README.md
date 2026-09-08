# Cellar

**A free, open, Proton-like layer for running Windows games on macOS (Apple Silicon).**

Cellar assembles a [Wine](https://www.winehq.org/) runner plus a graphics-translation backend
(Apple's **D3DMetal**, or the open-source **DXVK → MoltenVK** path) into per-game **bottles**,
driven by a community **profile database**. Each game names the **storefront** it came from, and
Cellar handles that store's shape: Windows **Steam** or Blizzard's **Battle.net** stood up inside the
bottle, or — for **GOG** — no client at all, just an OAuth token and a DRM-free installer. You sign in
once per store, not once per game. The engine is general: adding a game means adding a profile, not
rebuilding the layer.

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

## Three storefronts, told apart properly

A profile says `store = "steam"`, `"battlenet"`, `"gog"` or `"standalone"`, and that decides
everything downstream — which client `cellar setup` installs (if any), what "installed" and "signed
in" mean, how a launch is issued, and what the app tells you. The differences are real, and Cellar
refuses to paper over them:

| | Steam | Battle.net | GOG |
|---|---|---|---|
| Client in the bottle | yes | yes | **none** — Cellar talks to GOG over HTTP |
| Installing the client | silent (`/S`) | **not silent** — Blizzard's window opens and wants a few clicks, so Cellar warns you before it does | n/a |
| Signing in | once, in the client's window — **shared by every Steam game** | in the client's window | **once, OAuth** — covers your whole library |
| Who's signed in | readable (`loginusers.vdf`) — the app shows your account | **not published** — so Cellar shows no sign-in step and no false ✗ | Cellar holds the token, so it knows |
| Games are named by | AppID (`2688950`) | product code (`Fen` = Diablo IV) | `gog_product_id` |
| Installing a game | `cellar steam install <slug>` | opens Battle.net — Blizzard exposes no install URL a launcher can drive | `cellar gog install <slug>` — Cellar downloads and installs it |
| Launching | `steam://rungameid/…` into a silent client | `Battle.net.exe --exec="launch Fen"`, client warmed first | run the exe — nothing beside it |

```sh
# Diablo IV, via Battle.net
cellar setup --profile diablo-4     # runner + bottle + Battle.net (its installer needs a few clicks)
cellar battlenet open diablo-4      # sign in, install the game from the client
cellar launch diablo-4              # play — quitting the game closes the whole layer

# The Witcher 3, via GOG — DRM-free, so no store client is involved at all
cellar gog login                    # sign in once, for your whole GOG library
cellar gog install witcher-3        # Cellar downloads it and installs it silently
cellar launch witcher-3             # play
```

### You sign in once, not once per game

A bottle is per-game so each game keeps its own registry, runner and Wine version. The Steam *client*
is not per-game — it's your account's — so Cellar keeps **one** Windows Steam install in
`shared/steam` and symlinks every bottle to it. One sign-in, one 1.4 GB client, and a game you own
downloaded once instead of per bottle. `cellar steam share` migrates an existing setup and never
deletes a download.

`cellar accounts` (⌘⇧A in the app) shows where you're signed in — and only what Cellar can actually
check: your Steam account name, your GOG account name, and for Battle.net an honest "not published"
rather than a guess.

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
cellar steam open  planet-coaster-2 # opens Steam in the bottle — log in once, for every Steam game
cellar steam install planet-coaster-2  # opens the install dialog for PC2 (or install from the UI)
cellar launch      planet-coaster-2 # play (routes through Steam so DRM/auth work)
```

Signing in, wherever you are:

```sh
cellar accounts                     # where you're signed in, across every store
cellar steam login                  # QR sign-in for client-free downloads (nothing typed)
cellar steam share                  # one Steam install for every bottle (safe to re-run)
cellar gog login                    # OAuth, once, for your whole GOG library
cellar gog library                  # everything you own that runs on Windows
```

Surface it like a native game:

```sh
cellar steam add planet-coaster-2   # generates ~/Applications/Planet Coaster 2.app
                                    # and a non-Steam shortcut (quit Steam first)
```

Taking a game back off the machine:

```sh
cellar uninstall planet-coaster-2 --dry-run   # what would go, what would stay, and how much
cellar uninstall planet-coaster-2             # the game's files, its .app, its icon, its Steam entry
cellar uninstall planet-coaster-2 --bottle    # …and the bottle: the Wine prefix and the client in it
```

Removal is a plan first: Cellar prints every path it will delete with its size, and what it keeps —
your sign-in, the shared Steam install with everybody else's games, and the runner — then asks. It
never follows the bottle's symlink to the shared Steam library, and it only deletes a `.app` that
carries its own bundle identifier.

Other commands: `cellar runner list/install`, `cellar prefix list`, `cellar profiles list/show`,
`cellar fetch-depot <slug>` (client-free download), `cellar steam enable-windows-platform` (advanced).

---

## Contributing

New games are added as **profiles** — see [CONTRIBUTING.md](CONTRIBUTING.md). Cellar's policy is to
**upstream fixes** to Wine/DXVK where possible (one of the lessons from Whisky's end), keep the core
small, and let the community own the profile database.

## License

[GPL-3.0](LICENSE) © Cellar contributors. Bundled third-party components retain their own licenses
([THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)).
