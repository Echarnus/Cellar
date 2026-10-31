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
| `Sources/CellarKit/` | Core library — environment detection, bottles/prefixes, runners, profiles, the store plugins (`Store.swift`, `Steam.swift`, `BattleNet.swift`, `GOG.swift`/`GOGLibrary.swift`), sign-in (`Keychain.swift`, `SteamQRCode.swift`), downloading, app-bundle generation, the rolling log + diagnostics report (`Log.swift`, `Diagnostics.swift`). **All logic lives here.** |
| `Sources/cellar/` | Thin CLI over CellarKit (ArgumentParser). One file per command group under `Commands/`. |
| `Sources/CellarUI/` | The app's presentation primitives — store marks, lockups, the generated cover, and `Snapshot`, which renders a SwiftUI view to pixels. A library rather than part of the app, because **a test cannot import an executable**. |
| `Tests/CellarKitTests/` | Unit tests over the engine — parsing, the store table, launch routes, the readiness ladder and its copy, the profile database. Fast, hermetic, no Wine. |
| `Tests/CellarUITests/` | Store marks rendered offscreen and measured, plus the snapshot sheet. |
| `Tests/CellarIntegrationTests/` | Integration tests, tiered: bottles and app bundles always; a real runner, prefix and Windows game behind `CELLAR_IT=1`. See [`docs/TESTING.md`](docs/TESTING.md). |
| `Sources/CellarApp/` | Native SwiftUI "Steam-like" front-end. Hand-rolled `NSApplication` (no `@main` scene); **drives the `cellar` CLI as a subprocess** for actions, so it reuses every tested path. |
| `profiles/*.toml` | The per-game profile database — one file per game. Adding a game = adding a profile. |
| `Shim/` | `cellar-dock-shim.c` — the one piece of C in the repo. Inserted into a bottle's storefront client so it does not take a Dock icon while a game starts. Built by `Scripts/build-dock-shim.sh`, never by SwiftPM (it has to be universal). |
| `Scripts/` | Build/packaging: `install-app.sh`, `package.sh`, `build-dock-shim.sh`, `make-dmg.sh` (+ `make-dmg-background.swift`), `sign-app.sh`, `notarize.sh`, `import-signing-identity.sh`, `make-icon.swift`, `gen-site.py` (the GitHub Pages site generator), `release-notes.py` (a release's notes, from the issues it closed), `test.sh` (the test runner), `coverage.py` (the coverage ratchet), `check-pr.py` (the PR checklist). |
| `docs/` | `ARCHITECTURE.md`, `APP-ARCHITECTURE.md` (code layering + migration plan), `RELEASING.md`, `RESEARCH.md`, `ROADMAP.md`, `LEGAL.md`, `TESTING.md`. |
| `.github/` | Workflows (`ci`, `pr-checklist`, `codeql`, `dependency-review`, `scorecard`, `release`, `pages`, `labels`, `dependabot-auto-merge`), Dependabot, issue forms, the PR template, labels, rulesets. See `docs/RELEASING.md`. |
| `skills/`, `agents/` | Portable AI guidance (see below). Claude's copies are under `.claude/`. |

## Build, run, verify

Swift 6 toolchain, Apple Silicon, macOS 14+.

```sh
swift build                       # debug build
sh Scripts/test.sh                # the test suite, headless (~0.5s) — what CI runs
sh Scripts/test.sh --integration  # + the Wine tiers: real runner, real prefix, real Windows game
sh Scripts/test.sh --steam        # + tier D: a real Steam game (Fallout Shelter) downloaded and run
swift run cellar doctor           # sanity-check the machine
swift build -c release            # release build (what CI and the app installer use)
swift run cellar selftest         # in-repo smoke test
sh Scripts/install-app.sh         # build + install ~/Applications/Cellar.app
sh Scripts/build-dock-shim.sh     # build the Dock shim into .build/ (needed by `swift run cellar`)
python3 Scripts/gen-site.py       # regenerate the Pages site into site/
python3 Scripts/check-site.py     # check it: links, anchors, structure, contrast (what CI runs)
```

`swift build` does **not** build the Dock shim — it is a universal C dylib, and SwiftPM builds for one
architecture. `install-app.sh` and `package.sh` build it for you; run `Scripts/build-dock-shim.sh`
once by hand if you are testing launches straight from a checkout. Without it a bottle's Steam or
Battle.net simply keeps its Dock icon, which is what Cellar did before the shim existed.

> **Critical build gotcha.** A Nix/devenv shell on this machine exports `DEVELOPER_DIR`/`SDKROOT`
> pointing at a non-macOS SDK, which makes `swift build` fail or link the wrong SDK. Always build the
> app with:
>
> ```sh
> env -u DEVELOPER_DIR -u SDKROOT swift build -c release
> ```
>
> `Scripts/install-app.sh` and `Scripts/package.sh` already `unset` them internally (via
> `Scripts/select-xcode.sh`). When `xcode-select -p` is the Command Line Tools, they can build the
> CLI but **not the SwiftUI app** (no SwiftUI macro plugins: "SwiftUIMacros.StateMacro could not be
> found"), so the scripts switch to an installed Xcode. For a by-hand build of the app on such a Mac:
> `env -u SDKROOT DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release`.
> `install-app.sh` installs the app **and** the CLI it drives (`~/.local/bin/cellar` +
> `~/.local/share/cellar/`), so the two never drift apart.

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
   launching. Installs a real runner and starts a real Windows executable. CI runs it on every PR
   (the *Wine tiers* job), but run it yourself first for a change in this area — and before a release.
5. **A real game** — `sh Scripts/test.sh --steam` for anything touching depots, ownership or store
   credentials. Downloads Fallout Shelter (free, ~2 GB, Windows-only) from a real Steam depot and
   starts it. Needs `cellar steam login`; without it the tier skips and says so, which is not a pass.
6. **Behaviour** — the actual path you changed runs: the CLI command, or the installed app launched
   and exercised. GUI changes are verified by reinstalling (`install-app.sh`) and launching, not by
   reading the diff. Site changes are verified by generating and opening `site/index.html`.

Full map, including how to point tiers C and D at a specific game: [`docs/TESTING.md`](docs/TESTING.md).
The [verifier agent](agents/verifier.md) codifies these demands per kind of change.

### Every change arrives tested — no exceptions for AI authors

"It compiles" and a confident description are not verification. The author of a change, a person or
an AI agent, is the one who proves it works, in the PR, before anyone else spends time on it:

- **A PR that changes Swift under `Sources/` changes a test under `Tests/`** — one that would fail
  without the change. A bug fix starts with a test that reproduces the bug. The only way out is a
  line in the PR body, `No tests needed: <reason>`, and the reason has to be about this change.
- **Say what you ran, and show it.** The PR template's *How it was verified* section lists the
  ladder; tick only the rungs you actually climbed and paste the evidence (test count, command
  output, screenshot). A rung you could not climb stays unticked, with who has to climb it. An agent
  without a Mac says so — CI then is the build, and the PR says that too.
- **Coverage only goes up.** `sh Scripts/test.sh --coverage` measures CellarKit and CellarUI and
  fails below `Tests/coverage-baseline.json`. When a change raises it, raise the baseline in the same
  PR (`python3 Scripts/coverage.py --update <report>`).
- **The gates are checks, not trust.** CI runs the unit and hermetic integration tiers with coverage
  on both macOS images, the Wine tiers on a real runner, and *PR checklist*
  (`Scripts/check-pr.py`) on the description. None of them replaces climbing the ladder.

### Testing

```sh
sh Scripts/test.sh                    # the whole suite, seconds
sh Scripts/test.sh --filter Profile   # one part of it
sh Scripts/test.sh --coverage         # + line coverage, held to Tests/coverage-baseline.json
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
of each mark (Steam's big wheel upper-right and open, Blizzard's orb three-armed and not filled in,
GOG's mark a light tile carrying two lines of dark wordmark) rather than exact pixels, because a test
that broke on every gradient nudge would be deleted within a week, and one that passes a mirrored
logo is worthless. When you add a view worth verifying, put it in `CellarUI`.

Every run also writes `.build/ui-snapshots/store-marks-{light,dark}.png` — every mark, both themes,
every size it is used at, in one image. **Open that instead of launching the app** for a first look;
CI uploads it as an artifact on every PR. It does not replace rung 4 — a snapshot cannot show you
that a window resizes or a click lands — but it catches the wrong-looking before it reaches anyone.

**Launches are tested against a fake Wine.** `Tests/CellarKitTests/Support/FakeWine.swift` turns the
sandbox's stub runner into scripts that record every call — the exe, the prefix, the locale, the
profile's `[env]` — and keep a fake game alive for as long as a test asks. That is how the launch →
watch → shut-down path runs on every PR without a runner. Reach for it before adding a protocol or
a mock: a test double at the process boundary tests the code that actually ships.

## Stores are a first-class concept

A game names the storefront it came from (`store = "steam" | "battlenet" | "gog"`),
and that one field decides the whole pipeline: which client `cellar setup` installs (if any), what
"installed" and "signed in" mean, how a launch is issued, and the words the player reads. Read
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) → *The store layer* for the comparison table.

**Every game comes through a store — there is no other way in.** Cellar does not run games the
player downloaded or installed by hand, and it has no "no store" option anywhere: not in a
profile (`store` is required, and `Game.plan` refuses a profile without one), not in the CLI, not
in the app. A DRM-free game that launches without its client running is still a store's game,
installed from the player's own account. Don't add a storeless path back.

The differences are real, not cosmetic — the three that bite hardest:

- **Battle.net has no silent installer.** Steam's takes `/S`; Blizzard's does not exist. Setup must
  *warn the player* that a window will open, or an unexplained pause reads as a hang.
- **Battle.net does not publish who is signed in, or what you own.** Steam writes `loginusers.vdf`.
  So Cellar never shows a Battle.net sign-in step and never a ✓ or ✗ beside "account" — signing in
  is folded into "open the client", the one screen where the player can act on it. But the library
  still has to know whether this store is the player's, or Diablo IV shows up on a Mac that has
  never opened Battle.net. So Accounts asks once — "Add" (`cellar battlenet add`), a self-report,
  never called a sign-in — and `StoreLibrary.verdict` withholds the store's games until it is given.
- **Signing in is account-level, never per game — and Steam is asked exactly once.** The single
  Steam sign-in is Steam's QR device flow (`SteamAccount`), and it covers both *what you own* and
  *downloading it*. There is no Web API key and no separate download session; the in-bottle Windows
  client is not a second account but a runtime dependency of games whose DRM talks to a running
  Steam. Sign-in belongs in **Settings** (`cellar steam login`, ⌘⇧A), never on a game's page.
  `StoreDescriptor.authStyle` is the fact that decides which shape a store has.
- **The library is the games you own, not the catalogue.** `StoreLibrary` gates every profile on
  what the store confirmed, with three answers and not two — owned, not owned, *unverifiable* — and
  a store that can never answer (Battle.net) shows its games saying so. Adding a claim about the
  player's library without a store behind it is the one bug class `cellar selftest` covers directly.

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
- **Wine, runners, backends, bottles** → [`skills/wine-and-runners.md`](skills/wine-and-runners.md).
  The four load-bearing launch findings (no `/usr/bin/arch`, inherit-then-strip the environment,
  merge `WINEDLLOVERRIDES`), why WineForge is the default, bottle hygiene and teardown.
- **Game profiles** (`profiles/*.toml`) → [`skills/profiles.md`](skills/profiles.md). Three parsers
  read a profile and they disagree — scalars only, no `#` in values, no reliance on section scoping.
- **HTML / CSS / JS** (the static site) → [`skills/web.md`](skills/web.md). Theme-aware, responsive,
  no build step, data-driven from profiles.
- **Python** (`Scripts/gen-site.py`) → [`skills/python.md`](skills/python.md). Stdlib only, Python
  3.9 floor, escape every interpolation.
- **Shell + packaging + Info.plist** → [`skills/shell-and-packaging.md`](skills/shell-and-packaging.md).
  POSIX `sh`, `set -eu`, ShellCheck, the SDK-unset rule, case-insensitive-FS zip-naming trap,
  versionless DMG.
- **CI / releases / Pages** (`.github/workflows/`) → [`skills/ci.md`](skills/ci.md). Least-privilege
  `permissions:`, pin third-party actions to a SHA, never interpolate `${{ }}` into a `run:`.

## Adding a game

A game is a `profiles/<slug>.toml` — copy the closest existing one (`planet-coaster-2` for Steam,
`diablo-4` for Battle.net, `witcher-3` for GOG). Name its **`store`**, record verified facts (AppID *or* `product_code` +
`install_dir` + `exe`, engine, graphics API, arch), state DRM/anti-cheat **honestly**, pick `backend`
+ `fallback_backend`, and give a `status` + `notes` naming the hardware you tested on. The app shows
those facts verbatim, so "untested" must say so. See [`skills/profiles.md`](skills/profiles.md) for
the schema and its parser traps, and [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Git & releases

Cellar is delivered through GitHub, end to end. Full strategy: [`docs/RELEASING.md`](docs/RELEASING.md).

- **Every task has an issue.** Search before opening one, label it (`.github/labels.yml` is the set),
  and keep it to one outcome. The issue is what the release notes are built from, so its title is
  written for a player: "Dock says Wine while a game is playing", not "fix CFBundleName".
- **Every change is a pull request that closes its issue.** Branch from `main`, push, open a PR whose
  body says `Closes #N`, and turn on auto-merge (squash). It merges by itself once the required
  checks are green: CI, lint, CodeQL and dependency review. Nobody pushes to `main` directly; the
  ruleset in `.github/rulesets/main.json` enforces it.
- **The checks are a floor, not the ladder.** CI cannot launch the app or play a real game. Climb the
  verification ladder above before enabling auto-merge, and say in the PR which rung you reached —
  *PR checklist* fails a PR that doesn't, or that changes `Sources/` without touching `Tests/`.
- **Releases are SemVer tags (`vMAJOR.MINOR.PATCH`) we push ourselves.** The tag runs
  `release.yml`, which builds the downloads, writes the notes from the issues the release closed
  (`Scripts/release-notes.py`) and publishes the GitHub Release.
- **Commit messages:** state what was done, one subject line; a body only when the *why* isn't
  obvious. **No attribution trailers** (no `Co-Authored-By`, no "Generated with").
- **Never force-push or rewrite published history**, and never delete a branch someone else's
  session is working in.

## Hard project rules (never violate)

These are correctness *and* legality constraints. They override any convenience.

- **Never bundle Apple's D3DMetal** or any proprietary runtime in Cellar's source or release
  artifacts — it is grafted from community runners at runtime under Apple's non-commercial grant.
- **Never commit game files, bottles, runners, downloaded depots, or logs.**
- **Credentials stay in the keychain or a `0600` file, and never reach a log or a report.** Read
  [`docs/SECURITY.md`](docs/SECURITY.md) before touching a sign-in; a new place a credential can go
  needs a row there and a test in `CredentialStorageTests`.
- **Never add DRM or anti-cheat circumvention.** Cellar runs DRM *through* the layer, untouched.
- **Owned games only** — game data comes from the user's own authenticated Steam account.
- **Trademark-safe** — not affiliated with Apple, Valve, Blizzard, CodeWeavers, or Frontier. Store
  marks in the UI are **never bundled logo files**: Cellar shows the store's real icon by pointing at
  the copy already installed on the player's machine (`StoreIcon.swift` — the Mac app's `.icns`, the
  icon Wine extracted from the Windows client's `.exe`, or a loose `.ico`), the same graft-don't-bundle
  move it makes for D3DMetal, and draws its own vector mark when there is nothing to point at
  (`StoreMark.swift`). See [`NOTICE`](NOTICE) and [`docs/LEGAL.md`](docs/LEGAL.md).

## AI configuration in this repo

- [`AGENTS.md`](AGENTS.md) (this file) — portable guidelines, read by every agent tool.
- [`skills/`](skills/) — portable, tool-agnostic best-practice guides: UX, Swift, Wine/runners,
  profiles, web, Python, shell/packaging, CI. Index: [`skills/README.md`](skills/README.md).
- [`agents/`](agents/) — portable agent definitions (the verifier).
- [`.claude/`](.claude/) — **Claude-specific.** Claude Code does not read `AGENTS.md` directly, so
  [`.claude/CLAUDE.md`](.claude/CLAUDE.md) `@`-imports it, and `.claude/skills/` + `.claude/agents/`
  hold the Claude-format (auto-discovered) copies of the same skills and the verifier.
