# Skill: Python in Cellar (`pages/gen-site.py`)

There are three Python programs in this repo: the static-site generator, its checker
(`pages/check-site.py`, which CI runs on every site change), and the small
`app/Scripts/make-appcast.py` that writes the update feed (same rules: stdlib only, 3.9 floor, escape
every interpolation). Most of this file is about the generator. Best practices
for changing it. Portable guide; Claude's auto-discovered copy is
`.claude/skills/cellar-python/SKILL.md`. Read [`../AGENTS.md`](../AGENTS.md) first, and
[`web.md`](web.md) for the HTML/CSS bar the output is judged against — this file is about the
*generator*, that one is about the *page*.

## Two hard constraints

- **Standard library only. No dependencies, ever.** The site has no build step, no `requirements.txt`
  and no virtualenv; CI and the Pages workflow just run `python3 pages/gen-site.py`. Adding a
  dependency means adding an install step to two workflows and a toolchain to every contributor's
  machine, to save a few lines of stdlib.
- **Python 3.9 is the floor, and it is not hypothetical.** The system `python3` on this Mac is
  **3.9.6**, so the hand-rolled TOML fallback is the code path that actually runs locally, while CI
  runners (3.12+) take `tomllib`. No `match`, no PEP 604 `X | Y` annotations, no `tomllib` without
  the fallback. See [`profiles.md`](profiles.md) — **the same profile can parse differently on your
  machine than in CI**, and that is the single biggest trap in this file.

## Escape every interpolation

The page is built with f-strings, so every value interpolated into HTML must be escaped, and the
render functions alias `n = html.escape` to make that cheap. Every profile value is escaped, in text
*and* in attributes (`src`, `data-*`, classes) — "escape everything, without having to reason about
the source" is the only rule that stays true after someone adds a user-synced profile registry. The
exception is the FAQ's answers, which are HTML authored in the generator itself.

An unknown `store` or `status`, or a profile without `name`/`slug`, **fails the build with the
filename** rather than rendering a wrong card.

## Style

- **Match the file.** It uses `os.path`, not `pathlib`; f-strings; small module-level functions
  (`load_games`, `card`, `render`, `main`) and dict-shaped records. Ruff's `PTH` rules would push you
  to `pathlib` — that is a fine choice, but make it wholesale in its own commit, not by leaving half
  the script in each idiom.
- **Always pass `encoding="utf-8"` to `open()`**, and close what you open with a `with` block.
  Game names are not all ASCII.
- **Stay deterministic.** `sorted(glob(...))` and the explicit `sorted(games, key=…)` are why the
  generated page has a stable diff. Never iterate a set or an unsorted directory listing into output.
- **Fail loudly on bad input.** Validation exits non-zero with the filename; CI runs the generator
  on every site change, so a real failure there is free protection.
- **Both parsers, every time.** `CELLAR_TOML_FALLBACK=1` forces the hand-rolled parser even where
  `tomllib` exists; `pages.yml` builds the site both ways and diffs the output, so the 3.9 path is
  no longer exercised only on this Mac.

## Linting

**[Ruff](https://docs.astral.sh/ruff/) is the 2026 standard** — one Rust binary replacing flake8,
Black, isort and pyupgrade. Nothing is configured in this repo yet. If you add it, target the floor
so it doesn't suggest 3.10+ rewrites:

```toml
# pyproject.toml (only if we adopt it)
[tool.ruff]
target-version = "py39"
```

Run `ruff check app/Scripts/` and `ruff format --diff app/Scripts/`. Wiring it into `ci.yml` belongs with
[`ci.md`](ci.md) — as a real gate, not an `|| true` step.

## Don't

- **Don't hand-edit `pages/dist/index.html`.** It is generated; your change will be overwritten on the next
  push that touches a profile. Change the generator.
- **Don't hard-code a game.** The grid is data-driven from `profiles/*.toml` precisely so the page
  cannot drift from what Cellar supports.
- **Don't reach for a template engine.** f-strings plus `html.escape` are sufficient at this size and
  keep the zero-dependency rule intact.

## Verify

1. `python3 pages/gen-site.py` succeeds — note which parser you just exercised (3.9 here → the
   fallback; CI → `tomllib`).
2. Open `pages/dist/index.html`: correct title, working Download CTA, one card per profile, the icon
   present, no unrendered `{`/`}` markers.
3. Check it in light *and* dark and at a narrow width ([`web.md`](web.md)).
4. If you touched parsing, verify a profile with an awkward value — a `#`, an apostrophe, a
   non-ASCII name — through **both** paths.

Related: [`web.md`](web.md) · [`profiles.md`](profiles.md) · [`ci.md`](ci.md) ·
[`../agents/verifier.md`](../agents/verifier.md)
