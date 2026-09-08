---
name: cellar-python
description: Best practices for the one Python program in Cellar, Scripts/gen-site.py (the static-site generator). Use when editing the generator, its TOML parsing, or how it emits HTML. Covers the stdlib-only and Python-3.9 constraints, why the local and CI parsers differ, escaping every interpolation, encoding and file-handle hygiene, determinism, and Ruff.
---

# Cellar — Python (`Scripts/gen-site.py`)

The full guide is [`skills/python.md`](../../../skills/python.md); read it. This covers the
*generator*; the page it emits is [`cellar-web`](../cellar-web/SKILL.md). Key rules:

- **Standard library only, forever.** No dependencies, no build step, no virtualenv — CI and Pages
  just run `python3 Scripts/gen-site.py`.
- **Python 3.9 is the floor and it is live:** this machine's `python3` is 3.9.6, so the hand-rolled
  TOML fallback is the local path while CI (3.12+) uses `tomllib`. No `match`, no `X | Y`
  annotations. The same profile can parse differently in the two ([`cellar-profiles`](../cellar-profiles/SKILL.md)).
- **Escape every interpolation.** `card()` aliases `n = html.escape` for visible text but skips
  several attributes (`src`, `data-status`, `data-store`, the store CSS class) — and `data-status`
  falls back to the *raw* profile string for an unknown status. Wrap them.
- **Pass `encoding="utf-8"` to `open()`** (`main()` currently doesn't when writing `index.html`),
  and close what you open — the fallback parser iterates a bare `open()`.
- **Stay deterministic:** `sorted(glob(...))` and the explicit sort are why the page has a stable
  diff. Never iterate a set into output.
- **Match the file's idiom** (`os.path`, f-strings, small functions). Converting to `pathlib` is
  fine — wholesale, in its own commit, not half and half.
- **Don't hand-edit `site/index.html`**, don't hard-code a game, don't add a template engine.
- **Ruff** is the standard if we adopt linting (`target-version = "py39"`); nothing is configured yet.
- **Verify by rendering**: run it, open the page, check light/dark and a narrow width, and test an
  awkward value (a `#`, an apostrophe, a non-ASCII name) through **both** parsers.
