# skills/ — best-practice guides for Cellar

Portable, tool-agnostic guidance any AI agent (or human) can read. [`AGENTS.md`](../AGENTS.md) links
these for the language you're touching. Claude Code auto-discovers its own copies under
`.claude/skills/`, which point back here.

| Skill | Use when you're working on |
|---|---|
| [`swift.md`](swift.md) | `Sources/**` — CellarKit, the `cellar` CLI, or the SwiftUI app |
| [`web.md`](web.md) | the static site / `Scripts/gen-site.py` |
| [`shell-and-packaging.md`](shell-and-packaging.md) | `Scripts/*.sh`, the `.app`/DMG, releases |

Each guide ends with the **verification** its kind of change must pass — the same demands the
[verifier agent](../agents/verifier.md) enforces.
