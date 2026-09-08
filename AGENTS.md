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
into per-game **bottles**, driven by a **profile database**. There is a `cellar` CLI and a native
SwiftUI app (`CellarApp`), both over one core library (`CellarKit`).

Full picture: [`README.md`](README.md) · architecture: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
· roadmap: [`docs/ROADMAP.md`](docs/ROADMAP.md) · legal boundaries: [`docs/LEGAL.md`](docs/LEGAL.md).

## Repository structure

| Path | What lives there |
|---|---|
| `Sources/CellarKit/` | Core library — environment detection, bottles/prefixes, runners, profiles, Steam, downloading, app-bundle generation. **All logic lives here.** |
| `Sources/cellar/` | Thin CLI over CellarKit (ArgumentParser). One file per command group under `Commands/`. |
| `Sources/CellarApp/` | Native SwiftUI "Steam-like" front-end. Hand-rolled `NSApplication` (no `@main` scene); **drives the `cellar` CLI as a subprocess** for actions, so it reuses every tested path. |
| `profiles/*.toml` | The per-game profile database — one file per game. Adding a game = adding a profile. |
| `Scripts/` | Build/packaging: `install-app.sh`, `package.sh`, `make-dmg.sh`, `make-icon.swift`, `gen-site.py` (the GitHub Pages site generator). |
| `docs/` | `ARCHITECTURE.md`, `RELEASING.md`, `RESEARCH.md`, `ROADMAP.md`, `LEGAL.md`. |
| `.github/workflows/` | `ci.yml`, `release.yml`, `pages.yml`. |
| `skills/`, `agents/` | Portable AI guidance (see below). Claude's copies are under `.claude/`. |

## Build, run, verify

Swift 6 toolchain, Apple Silicon, macOS 13+.

```sh
swift build                       # debug build
swift run cellar doctor           # sanity-check the machine
swift build -c release            # release build (what CI and the app installer use)
swift run cellar selftest         # in-repo smoke test
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
2. **Self-test** — `swift run cellar selftest` passes.
3. **Behaviour** — the actual path you changed runs: the CLI command, or the installed app launched
   and exercised. GUI changes are verified by reinstalling (`install-app.sh`) and launching, not by
   reading the diff. Site changes are verified by generating and opening `site/index.html`.

The [verifier agent](agents/verifier.md) codifies these demands per kind of change.

## Coding guidelines

Match the surrounding code. Small types, clear names, comments only where intent isn't obvious. Then,
per language:

- **Swift / SwiftUI / AppKit** → [`skills/swift.md`](skills/swift.md). Load-bearing project rules
  (AttributeGraph crash from detail-pane animation, `HSplitView` not `NavigationSplitView`, the
  hand-built menu bar, keeping logic in CellarKit) live there — read it before touching
  `Sources/**`.
- **HTML / CSS / JS** (the static site) → [`skills/web.md`](skills/web.md). Theme-aware, responsive,
  no build step, data-driven from profiles.
- **Shell + packaging + Info.plist** → [`skills/shell-and-packaging.md`](skills/shell-and-packaging.md).
  POSIX `sh`, `set -e`, the SDK-unset rule, case-insensitive-FS zip-naming trap, versionless DMG.

## Adding a game

A game is a `profiles/<slug>.toml` — copy `profiles/planet-coaster-2.toml`. Record verified facts
(AppID, engine, graphics API, arch), state DRM/anti-cheat **honestly**, pick `backend` +
`fallback_backend`, set the install `method`, and a `status` + `notes` with the hardware you tested
on. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

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
- **Trademark-safe** — not affiliated with Apple, Valve, CodeWeavers, or Frontier. See
  [`NOTICE`](NOTICE) and [`docs/LEGAL.md`](docs/LEGAL.md).

## AI configuration in this repo

- [`AGENTS.md`](AGENTS.md) (this file) — portable guidelines, read by every agent tool.
- [`skills/`](skills/) — portable, tool-agnostic best-practice guides (Swift, web, shell).
- [`agents/`](agents/) — portable agent definitions (the verifier).
- [`.claude/`](.claude/) — **Claude-specific.** Claude Code does not read `AGENTS.md` directly, so
  [`.claude/CLAUDE.md`](.claude/CLAUDE.md) `@`-imports it, and `.claude/skills/` + `.claude/agents/`
  hold the Claude-format (auto-discovered) copies of the same skills and the verifier.
