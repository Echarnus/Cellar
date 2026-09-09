# AGENTS.md — working on Cellar

Instructions for AI coding agents (and new human contributors) working in this repository. This is
the **portable, single source of truth**; every agent tool reads `AGENTS.md`. Tool-specific setup
lives elsewhere and points back here — Claude Code uses [`.claude/CLAUDE.md`](.claude/CLAUDE.md),
which imports this file.

Read this first, then the linked doc for whatever you're touching. Don't re-derive facts that are
already written down.

---

## What Cellar is

A free, GPL-3.0, Proton-like layer that runs **Windows games on Apple Silicon Macs**. It assembles a
Wine runner + a graphics-translation backend (Apple **D3DMetal**, or open-source **DXVK → MoltenVK**)
into per-game **bottles**, driven by a **profile database**, and stands the game's own **storefront
client** up inside the bottle — Windows **Steam**, or Blizzard's **Battle.net**. There is a `cellar`
CLI and a native SwiftUI app (`CellarApp`), both over one core library (`CellarKit`).

Full picture: [`README.md`](README.md) · architecture: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
· roadmap: [`docs/ROADMAP.md`](docs/ROADMAP.md) · legal boundaries: [`docs/LEGAL.md`](docs/LEGAL.md).

## Repository structure

| Path | What lives there |
|---|---|
| `Sources/CellarKit/` | Core library — environment detection, bottles/prefixes, runners, profiles, the store plugins (`Store.swift`, `Steam.swift`, `BattleNet.swift`, `GOG.swift`/`GOGLibrary.swift`), sign-in (`Keychain.swift`, `SteamQRCode.swift`), downloading, app-bundle generation. **All logic lives here.** |
| `Sources/cellar/` | Thin CLI over CellarKit (ArgumentParser). One file per command group under `Commands/`. |
| `Sources/CellarUI/` | The app's presentation primitives — store marks, lockups, the generated cover, and `Snapshot`, which renders a SwiftUI view to pixels. A library rather than part of the app, because **a test cannot import an executable**. |
| `Tests/` | `CellarKitTests` (engine logic, the profile database) and `CellarUITests` (marks rendered offscreen and measured). Run with `sh Scripts/test.sh`. |
| `Sources/CellarApp/` | Native SwiftUI "Steam-like" front-end. Hand-rolled `NSApplication` (no `@main` scene); **drives the `cellar` CLI as a subprocess** for actions, so it reuses every tested path. |
| `profiles/*.toml` | The per-game profile database — one file per game. Adding a game = adding a profile. |
| `Tests/CellarKitTests/` | Unit tests — parsing, the store table, launch routes, the readiness ladder and its copy. Fast, hermetic, no Wine. |
| `Tests/CellarIntegrationTests/` | Integration tests, tiered: bottles and app bundles always; a real runner, prefix and Windows game behind `CELLAR_IT=1`. See [`docs/TESTING.md`](docs/TESTING.md). |
| `Scripts/` | Build/packaging: `install-app.sh`, `package.sh`, `make-dmg.sh`, `make-icon.swift`, `gen-site.py` (the GitHub Pages site generator), `test.sh` (the test runner). |
| `docs/` | `ARCHITECTURE.md`, `RELEASING.md`, `RESEARCH.md`, `ROADMAP.md`, `LEGAL.md`. |
| `.github/workflows/` | `ci.yml`, `release.yml`, `pages.yml`. |
| `skills/`, `agents/` | Portable AI guidance (see below). Claude's copies are under `.claude/`. |

## Build, run, verify

Swift 6 toolchain, Apple Silicon, macOS 13+.

```sh
swift build                       # debug build
sh Scripts/test.sh                # the test suite (headless, ~0.5s)
swift run cellar doctor           # sanity-check the machine
swift build -c release            # release build (what CI and the app installer use)
swift run cellar selftest         # in-repo smoke test
sh Scripts/test.sh                # unit tests + hermetic integration tier (what CI runs)
sh Scripts/test.sh --integration  # + the Wine tiers: real prefix, real Windows game
sh Scripts/install-app.sh         # build + install ~/Applications/Cellar.app
python3 Scripts/gen-site.py       # regenerate the Pages site into site/
```

> **Critical build gotcha.** A Nix/devenv shell on this machine exports `DEVELOPER_DIR`/`SDKROOT`
> pointing at a non-macOS SDK, which makes `swift build` fail or link the wrong SDK. Always build the
> app with:
>
> ```sh
> env -u DEVELOPER_DIR -u SDKROOT swift build -c release
> ```
>
> `Scripts/install-app.sh` and `Scripts/package.sh` already `unset` them internally.

### Verification ladder — the "appropriate demands"

Climb to the **highest rung available** before claiming a change is done. Never claim done without
verifying, and if you cannot verify, say so and name what needs manual checking.

1. **Builds** — `env -u DEVELOPER_DIR -u SDKROOT swift build -c release` is clean.
2. **Tests** — `sh Scripts/test.sh` passes. This is the rung to reach for first: it runs headless in
   under a second, so it costs nothing and it does not take the machine away from whoever is using
   it. A change to a profile, a store, a launch route, a mark or any player-visible wording is
   expected to be *covered* here, not merely to leave it green. See *Testing* below.
3. **Self-test** — `swift run cellar selftest` passes.
4. **Wine tiers** — `sh Scripts/test.sh --integration` for anything touching runners, prefixes or
   launching. Installs a real runner and starts a real Windows executable, so it is a local rung,
   not a CI one — and it is the rung to climb before a release.
5. **Behaviour** — the actual path you changed runs: the CLI command, or the installed app launched
   and exercised. GUI changes are verified by reinstalling (`install-app.sh`) and launching, not by
   reading the diff. Site changes are verified by generating and opening `site/index.html`.

Full map, including how to point tier C at a specific game: [`docs/TESTING.md`](docs/TESTING.md).
The [verifier agent](agents/verifier.md) codifies these demands per kind of change.

### Testing

```sh
sh Scripts/test.sh                    # the whole suite, ~0.5s
sh Scripts/test.sh --filter Profile   # one part of it
```

Use the script rather than a bare `swift test`: swift-testing ships as a framework inside the
developer directory, and this machine's `xcode-select` points at a Nix SDK that has none — so
`swift test` fails with *"no such module 'Testing'"* until the framework search path is supplied.
`Scripts/test.sh` finds a developer directory that really has it and passes the paths through.

Three targets, and the split matters:

| Target | Covers | Why it exists |
|---|---|---|
| `CellarKit` | the engine | logic |
| `CellarUI` | store marks, lockups, the generated cover, `Snapshot` | **a test cannot import an executable**, so anything to be verified without launching the app lives here, not in `CellarApp` |
| `CellarApp` | windows, menus, state, the CLI subprocess | the part that genuinely needs launching |

**`Tests/CellarUITests` renders SwiftUI offscreen and measures the pixels.** That is what lets a
user-visible change be checked in the background instead of taking over the machine — and it is a
real check, not a proxy: the marks are drawn, then measured. It asserts the *identifying* properties
of each mark (Steam's big wheel upper-right and open, Blizzard's orb not filled in) rather than exact
pixels, because a test that broke on every gradient nudge would be deleted within a week, and one
that passes a mirrored logo is worthless. When you add a view worth verifying, put it in `CellarUI`.

Every run also writes `.build/ui-snapshots/store-marks-{light,dark}.png` — every mark, both themes,
every size it is used at, in one image. **Open that instead of launching the app** for a first look;
CI uploads it as an artifact on every PR. It does not replace rung 4 — a snapshot cannot show you
that a window resizes or a click lands — but it catches the wrong-looking before it reaches anyone.

## Stores are a first-class concept

A game names the storefront it came from (`store = "steam" | "battlenet" | "gog" | "standalone"`),
and that one field decides the whole pipeline: which client `cellar setup` installs (if any), what
"installed" and "signed in" mean, how a launch is issued, and the words the player reads. Read
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) → *The store layer* for the comparison table.

The differences are real, not cosmetic — the three that bite hardest:

- **Battle.net has no silent installer.** Steam's takes `/S`; Blizzard's does not exist. Setup must
  *warn the player* that a window will open, or an unexplained pause reads as a hang.
- **Battle.net does not publish who is signed in.** Steam writes `loginusers.vdf`. So Cellar never
  shows a Battle.net sign-in step and never a ✗ beside "account" — it folds signing in into "open the
  client", the one screen where the player can act on it.
- **Signing in is account-level, never per game.** One Windows Steam install lives in `shared/steam`
  and every Steam bottle symlinks to it, and GOG's sign-in is an OAuth token Cellar holds. So a
  sign-in belongs to the **Accounts** screen (`cellar accounts`, ⌘⇧A), not to a game's page.
  `StoreDescriptor.authStyle` is the fact that decides which shape a store has.

Encode any such difference in **`GameStore.descriptor`** (`Sources/CellarKit/Store.swift`), never as a
special case inside a view or a command. Adding a store = a `GameStore` case, a `*Bottle` type, a
branch in `Game.setUp`/`Game.launch`, and a CLI command group. Nothing else should need to know.

## UX/UI is a requirement, not a finishing touch

**The interface is the product.** Cellar exists to make a Windows game start on a Mac, and the only
way anyone experiences that is the app in front of them. A change that compiles but reads like a
developer tool has not landed. Hold every user-visible change — app, CLI wording, error text — to
[`skills/ux.md`](skills/ux.md), which is not optional reading:

- One obvious next action per screen, with a plain sentence saying what will happen.
- Every state designed: empty, loading, first-run, busy, error; light *and* dark; minimum width.
- **Honesty**: never a ✓ for something Cellar cannot check, never an implied promise about a step the
  player will actually have to perform themselves.
- Stores are told apart by **position + mark + word** together; colour never carries it alone.
- **Verify by launching and looking**, never by reading the diff.

## Coding guidelines

Match the surrounding code. Small types, clear names, comments only where intent isn't obvious. Then,
per language:

- **Anything a player sees** → [`skills/ux.md`](skills/ux.md). Read it before the language guide;
  it is the bar the change will be judged against.
- **Swift / SwiftUI / AppKit** → [`skills/swift.md`](skills/swift.md). Load-bearing project rules
  (AttributeGraph crash from detail-pane animation, `HSplitView` not `NavigationSplitView`, the
  hand-built menu bar, keeping logic in CellarKit) live there — read it before touching
  `Sources/**`.
- **HTML / CSS / JS** (the static site) → [`skills/web.md`](skills/web.md). Theme-aware, responsive,
  no build step, data-driven from profiles.
- **Shell + packaging + Info.plist** → [`skills/shell-and-packaging.md`](skills/shell-and-packaging.md).
  POSIX `sh`, `set -e`, the SDK-unset rule, case-insensitive-FS zip-naming trap, versionless DMG.

## Adding a game

A game is a `profiles/<slug>.toml` — copy the closest existing one (`planet-coaster-2` for Steam,
`diablo-4` for Battle.net, `witcher-3` for GOG). Name its **`store`**, record verified facts (AppID *or* `product_code` +
`install_dir` + `exe`, engine, graphics API, arch), state DRM/anti-cheat **honestly**, pick `backend`
+ `fallback_backend`, and give a `status` + `notes` naming the hardware you tested on. The app shows
those facts verbatim, so "untested" must say so. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Git & releases

- **Trunk-based.** `main` is always releasable; feature branch → PR → `main`. Releases are SemVer
  tags (`vMAJOR.MINOR.PATCH`) on `main`. Full strategy: [`docs/RELEASING.md`](docs/RELEASING.md).
- **Commit messages:** state what was done, one subject line; a body only when the *why* isn't
  obvious. **No attribution trailers** (no `Co-Authored-By`, no "Generated with").
- **Never** push to `main`/`master`, force-push, or merge on the user's behalf — open a PR.

## Hard project rules (never violate)

These are correctness *and* legality constraints. They override any convenience.

- **Never bundle Apple's D3DMetal** or any proprietary runtime in Cellar's source or release
  artifacts — it is grafted from community runners at runtime under Apple's non-commercial grant.
- **Never commit game files, bottles, runners, downloaded depots, or logs.**
- **Never add DRM or anti-cheat circumvention.** Cellar runs DRM *through* the layer, untouched.
- **Owned games only** — game data comes from the user's own authenticated Steam account.
- **Trademark-safe** — not affiliated with Apple, Valve, Blizzard, CodeWeavers, or Frontier. Store
  marks in the UI are **drawn in code** (`StoreMark.swift`), never bundled logo files. See
  [`NOTICE`](NOTICE) and [`docs/LEGAL.md`](docs/LEGAL.md).

## AI configuration in this repo

- [`AGENTS.md`](AGENTS.md) (this file) — portable guidelines, read by every agent tool.
- [`skills/`](skills/) — portable, tool-agnostic best-practice guides (UX, Swift, web, shell).
- [`agents/`](agents/) — portable agent definitions (the verifier).
- [`.claude/`](.claude/) — **Claude-specific.** Claude Code does not read `AGENTS.md` directly, so
  [`.claude/CLAUDE.md`](.claude/CLAUDE.md) `@`-imports it, and `.claude/skills/` + `.claude/agents/`
  hold the Claude-format (auto-discovered) copies of the same skills and the verifier.
