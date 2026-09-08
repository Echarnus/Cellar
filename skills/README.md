# skills/ — best-practice guides for Cellar

Portable, tool-agnostic guidance any AI agent (or human) can read. [`AGENTS.md`](../AGENTS.md) links
these for the language you're touching. Claude Code auto-discovers its own copies under
`.claude/skills/`, which point back here.

| Skill | Use when you're working on |
|---|---|
| [`ux.md`](ux.md) | **anything a player sees** — the app, CLI wording, errors. Read this first |
| [`swift.md`](swift.md) | `Sources/**` — CellarKit, the `cellar` CLI, or the SwiftUI app |
| [`wine-and-runners.md`](wine-and-runners.md) | the translation layer — runners, backends, bottles, launching |
| [`profiles.md`](profiles.md) | `profiles/*.toml` — adding a game, changing the schema |
| [`web.md`](web.md) | the static site (the page itself) |
| [`python.md`](python.md) | `Scripts/gen-site.py` (the generator that emits it) |
| [`shell-and-packaging.md`](shell-and-packaging.md) | `Scripts/*.sh`, the `.app`/DMG, releases |
| [`ci.md`](ci.md) | `.github/workflows/**` — CI, releases, Pages |

Each guide ends with the **verification** its kind of change must pass — the same demands the
[verifier agent](../agents/verifier.md) enforces.

Two of these are rules-over-receipts: [`wine-and-runners.md`](wine-and-runners.md) and
[`profiles.md`](profiles.md) state what to do, while the evidence behind them (versions, symbolicated
crashes, sources) lives in [`../docs/RESEARCH.md`](../docs/RESEARCH.md). Add a finding there and the
rule here — not the same paragraph in both.
