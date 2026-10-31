# Contributing to Cellar

Thanks for helping! Cellar's design splits cleanly into a **general engine** and a **per-game
profile database**, so most contributions fall into one of two buckets.

## 1. Add or improve a game profile (the common case)

A game is supported by adding a `profiles/<slug>.toml`. Start from the closest existing one:
[`profiles/planet-coaster-2.toml`](profiles/planet-coaster-2.toml) for a Steam title,
[`profiles/diablo-4.toml`](profiles/diablo-4.toml) for a Battle.net one. A good profile:

- names its **`store`** — `steam`, `battlenet` or `gog`. Every game comes from a store; a DRM-free
  Steam game is still `steam`, with `needs_live_session = false` so no Steam client is stood up. This
  one field decides how Cellar installs, launches and describes the game;
- identifies the game the way its store does: `steam_appid` for Steam, or `product_code` +
  `install_dir` + `exe` for Battle.net (the last two are how Cellar knows it is installed and
  running, since Blizzard keeps that in a database Cellar doesn't parse);
- records the verified facts: engine, graphics API, architecture, developer, release date — **the app
  shows these verbatim**, so an unknown is better left out than guessed;
- states **anti-cheat** and **DRM** honestly (Cellar will not support titles requiring kernel
  anti-cheat circumvention, and never circumvents DRM);
- picks a `backend` (`d3dmetal` for modern DX11/12 on Apple Silicon; `dxvk` for DX9/older or as a
  fallback) and a `fallback_backend`;
- documents the install `method` (`windows-steam-in-bottle`, `battlenet-in-bottle`, or `depot`);
- includes a `status` (`playable` / `experimental` / `untested` / `broken`) and `notes` with the
  hardware/macOS you tested on. **`untested` is a fine thing to submit; a wrong `playable` is not** —
  the app puts that badge in front of someone about to start a 90 GB download;
- may supply `[art] art_portrait` / `art_hero` when the store publishes no artwork a launcher can
  address (Battle.net doesn't). Link images that are publicly served and unauthenticated.

Cite sources for non-obvious claims in the PR description.

## 2. Work on the engine (Swift)

- `app/Packages/CellarData/Sources/CellarData` — the core library (environment, bottles, runners, profiles, the store
  clients). The CLI and the SwiftUI app both import this; **all logic belongs here**.
- `app/src/cellar` — the CLI (one file per command group under `Commands/`).
- `app/src/CellarApp` — the SwiftUI app. Anything a player sees is held to
  [`skills/ux.md`](skills/ux.md); read it before you start, and verify by launching the app, not by
  reading your diff.
- Adding a **store** is a `GameStore` case, a `*Bottle` type beside `SteamBottle`/`BattleNetBottle`,
  a branch in `Game.setUp`/`Game.launch`, and a CLI command group. Per-store *behaviour* goes in
  `GameStore.descriptor`, never a `switch` inside a view.

- **Translations** live in `app/Resources/Localization/<lang>.lproj/Localizable.strings`, keyed by the
  app's English text. A new string on a screen needs a Dutch line there (the tests say which), and a
  new language is a copy of `nl.lproj` plus its code in the scripts' `CFBundleLocalizations` — see
  [`skills/ux.md`](skills/ux.md) → *Localization*.

Build and check before opening a PR:

```sh
cd app
swift build
sh Scripts/test.sh --coverage     # unit + hermetic integration tests, coverage held to the baseline
sh Scripts/test.sh --integration  # for runners, prefixes, launching: a real Windows exe under Wine
swift run cellar selftest
```

**Every PR that changes Swift under `Sources/` adds or updates a test** that would fail without the
change; a bug fix starts with a test that reproduces the bug. The PR template asks how you verified
the change: tick only what you actually ran and paste the evidence. The *PR checklist* check holds
every PR to this — whether a person or an AI agent wrote it. See [`docs/TESTING.md`](docs/TESTING.md)
for where each kind of test goes and the test doubles that make launches testable without Wine.

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
