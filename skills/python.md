# Skill: Python in Cellar (`Scripts/gen-site.py`)

There is exactly one Python program in this repo: the 266-line static-site generator. Best practices
for changing it. Portable guide; Claude's auto-discovered copy is
`.claude/skills/cellar-python/SKILL.md`. Read [`../AGENTS.md`](../AGENTS.md) first, and
[`web.md`](web.md) for the HTML/CSS bar the output is judged against — this file is about the
*generator*, that one is about the *page*.

## Two hard constraints

- **Standard library only. No dependencies, ever.** The site has no build step, no `requirements.txt`
  and no virtualenv; CI and the Pages workflow just run `python3 Scripts/gen-site.py`. Adding a
  dependency means adding an install step to two workflows and a toolchain to every contributor's
  machine, to save a few lines of stdlib.
- **Python 3.9 is the floor, and it is not hypothetical.** The system `python3` on this Mac is
  **3.9.6**, so the hand-rolled TOML fallback is the code path that actually runs locally, while CI
  runners (3.12+) take `tomllib`. No `match`, no PEP 604 `X | Y` annotations, no `tomllib` without
  the fallback. See [`profiles.md`](profiles.md) — **the same profile can parse differently on your
  machine than in CI**, and that is the single biggest trap in this file.

## Escape every interpolation

The page is built with f-strings, so every value interpolated into HTML must be escaped, and
`card()` aliases `n = html.escape` to make that cheap. It is applied consistently to the visible
text — and **not** applied to several attribute values: `src="{g['portrait']}"`,
`data-status="{g['status']}"`, `data-store="{g['storekey']}"` and `class="tag store {store['cls']}"`.

`status` is the one to fix first: `STATUS.get(...)` falls back to the **raw profile string** when the
value is outside the known vocabulary, and that raw string lands in an attribute unquoted-escaped. A
profile is repo-controlled, so this is not a live vulnerability — but "escape everything, without
having to reason about the source" is the only rule that stays true after someone adds a
user-synced profile registry. Wrap them.

## Style

- **Match the file.** It uses `os.path`, not `pathlib`; f-strings; small module-level functions
  (`load_games`, `card`, `render`, `main`) and dict-shaped records. Ruff's `PTH` rules would push you
  to `pathlib` — that is a fine choice, but make it wholesale in its own commit, not by leaving half
  the script in each idiom.
- **Always pass `encoding="utf-8"` to `open()`.** `main()` currently writes `index.html` without one,
  so the output encoding depends on the machine's locale. Game names are not all ASCII.
- **Close what you open.** `parse_toml`'s fallback iterates `open(path, encoding="utf-8")` directly,
  leaving the handle to the garbage collector. Use a `with` block.
- **Stay deterministic.** `sorted(glob(...))` and the explicit `sorted(games, key=…)` are why the
  generated page has a stable diff. Never iterate a set or an unsorted directory listing into output.
- **Fail loudly on bad input.** A malformed profile currently produces a silently wrong card. If you
  add validation, exit non-zero with the filename — CI runs this generator as a sanity step, so a
  real failure there is free protection.

## Linting

**[Ruff](https://docs.astral.sh/ruff/) is the 2026 standard** — one Rust binary replacing flake8,
Black, isort and pyupgrade. Nothing is configured in this repo yet. If you add it, target the floor
so it doesn't suggest 3.10+ rewrites:

```toml
# pyproject.toml (only if we adopt it)
[tool.ruff]
target-version = "py39"
```

Run `ruff check Scripts/` and `ruff format --diff Scripts/`. Wiring it into `ci.yml` belongs with
[`ci.md`](ci.md) — as a real gate, not an `|| true` step.

## Don't

- **Don't hand-edit `site/index.html`.** It is generated; your change will be overwritten on the next
  push that touches a profile. Change the generator.
- **Don't hard-code a game.** The grid is data-driven from `profiles/*.toml` precisely so the page
  cannot drift from what Cellar supports.
- **Don't reach for a template engine.** f-strings plus `html.escape` are sufficient at this size and
  keep the zero-dependency rule intact.

## Verify

1. `python3 Scripts/gen-site.py` succeeds — note which parser you just exercised (3.9 here → the
   fallback; CI → `tomllib`).
2. Open `site/index.html`: correct title, working Download CTA, one card per profile, the icon
   present, no unrendered `{`/`}` markers.
3. Check it in light *and* dark and at a narrow width ([`web.md`](web.md)).
4. If you touched parsing, verify a profile with an awkward value — a `#`, an apostrophe, a
   non-ASCII name — through **both** paths.

Related: [`web.md`](web.md) · [`profiles.md`](profiles.md) · [`ci.md`](ci.md) ·
[`../agents/verifier.md`](../agents/verifier.md)
