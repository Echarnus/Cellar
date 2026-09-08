---
name: cellar-profiles
description: Best practices for Cellar's game profile database (profiles/*.toml). Use when adding a game, editing a profile, or changing the schema or anything that reads it. Covers the three independent parsers that disagree (tomllib, the Python 3.9 fallback, and the Swift line scanner), the flat-scan and inline-comment traps, the required shape and vocabularies, the honesty rules for status/notes/DRM, and the artwork boundary.
---

# Cellar — game profiles

The full guide is [`skills/profiles.md`](../../../skills/profiles.md); read it before adding or
changing a profile. Key rules:

- **Three parsers read a profile and they disagree.** `tomllib` (CI, Python 3.11+), a hand-rolled
  fallback (this machine — system `python3` is 3.9), and `ProfileStore.fields()`/`.env()` in Swift.
  So: **scalars only** (no arrays, inline tables or multi-line strings); **no `#` inside values**
  (Python cuts at any `#`, Swift only at `" #"`); and **don't rely on section scoping** — the Swift
  scan is flat and last-wins, so `[game] product_code` and `[install] product_code` are one key.
  The site can render differently locally than in CI; know which parser you exercised.
- **`store` decides the whole pipeline** — `steam` | `battlenet` | `standalone`, spelled exactly (an
  unknown value is treated as Steam). `status` is `playable` | `experimental` | `untested`.
- **Honesty is enforced.** The app shows these fields verbatim. `status` describes what *you ran*;
  `notes` names the hardware and OS; DRM and anti-cheat are stated precisely and separately (Denuvo
  is anti-tamper DRM, not anti-cheat). Untested means untested.
- **Comment the *why* in the file** — existing profiles explain why `Fen` is Diablo IV's product
  code and why `MTL_DEBUG_LAYER=1` is on. A profile is executable documentation.
- **Don't add a fourth spelling** of "needs a live client": `needs_live_session` is canonical,
  `needs_live_steam` is legacy-but-read, `requires_live_steam_session` is read by nothing.
- **Artwork:** Steam art is derived from the AppID; non-Steam profiles supply `art_portrait`
  themselves. Never bundle store or publisher artwork in the repo.
- **Verify:** regenerate the site *and* check the app/CLI, with an awkward value through both parsers.

Related: [`cellar-wine`](../cellar-wine/SKILL.md) · [`cellar-python`](../cellar-python/SKILL.md) ·
[`cellar-ux`](../cellar-ux/SKILL.md). Before reporting done, run the **cellar-verifier** agent.
