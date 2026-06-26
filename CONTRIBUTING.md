# Contributing to Cellar

Thanks for helping! Cellar's design splits cleanly into a **general engine** and a **per-game
profile database**, so most contributions fall into one of two buckets.

## 1. Add or improve a game profile (the common case)

A game is supported by adding a `profiles/<slug>.toml`. Use
[`profiles/planet-coaster-2.toml`](profiles/planet-coaster-2.toml) as the template. A good profile:

- records the verified facts: Steam AppID, engine, graphics API, architecture;
- states **anti-cheat** and **DRM** honestly (Cellar will not support titles requiring kernel
  anti-cheat circumvention, and never circumvents DRM);
- picks a `backend` (`d3dmetal` for modern DX11/12 on Apple Silicon; `dxvk` for DX9/older or as a
  fallback) and a `fallback_backend`;
- documents the install `method` (usually `windows-steam-in-bottle`);
- includes a `status` (`working` / `playable` / `experimental` / `broken`) and `notes` with the
  hardware/macOS you tested on.

Cite sources for non-obvious claims in the PR description.

## 2. Work on the engine (Swift)

- `Sources/CellarKit` — the core library (environment, bottles, runners, profiles). The future
  SwiftUI app imports this.
- `Sources/cellar` — the CLI (one file per command group under `Commands/`).

Build and check before opening a PR:

```sh
swift build
swift run cellar doctor
swift test            # once the test target lands (Phase 1)
```

Match the surrounding style: small types, clear names, comments only where intent isn't obvious.

## Project principles

- **Upstream fixes.** Where a fix belongs in Wine / DXVK / MoltenVK, send it there too. One reason
  Whisky was wound down was that it gave little back to the projects it depended on — Cellar aims not
  to repeat that.
- **Stay free and legal.** Never commit Apple's D3DMetal or any game files. Never add DRM/anti-cheat
  circumvention. Only ever assume the user owns their games. See [docs/LEGAL.md](docs/LEGAL.md).
- **Keep the core small.** Generality lives in the profile database, not in special-casing the engine.

## Licensing of contributions

By contributing you agree your contributions are licensed under the project's **GPL-3.0** license.
