# agents/ — agent definitions for Cellar

Portable, tool-agnostic agent definitions. Claude Code's spawnable copies (with the frontmatter it
needs) live under `.claude/agents/`.

| Agent | Role |
|---|---|
| [`verifier.md`](verifier.md) | Read-only reviewer that checks a change against Cellar's verification ladder and hard rules before it's called done. |

See [`AGENTS.md`](../AGENTS.md) for the guidelines these agents enforce and [`skills/`](../skills/)
for the per-language demands.
