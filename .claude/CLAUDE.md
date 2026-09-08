# CLAUDE.md

Claude Code does not read `AGENTS.md` automatically, so import it — it is the single source of truth
for how to work in this repo (structure, build, verification ladder, coding guidelines, hard rules):

@../AGENTS.md

## Claude-specific notes

Everything a human or another agent needs is in `AGENTS.md` and `skills/` — keep this file thin.

### Skills (auto-discovered)

`.claude/skills/` mirrors the portable [`skills/`](../skills/) as Claude-format skills. Invoke the
one matching your work; each points back at the portable guide for the full detail:

- **cellar-swift** — `Sources/**` (CellarKit, the CLI, the SwiftUI app).
- **cellar-web** — the static site / `Scripts/gen-site.py`.
- **cellar-shell** — `Scripts/*.sh`, the `.app`/DMG, releases.

### Verifier subagent

`.claude/agents/cellar-verifier.md` is the spawnable form of [`agents/verifier.md`](../agents/verifier.md).
Run it (read-only) before reporting any change to `Sources/**`, `Scripts/**`, `profiles/**`, or the
site as done.

### Build reminder

Build with `env -u DEVELOPER_DIR -u SDKROOT swift build -c release` — a Nix/devenv shell exports an
SDK that breaks a plain `swift build`. GUI changes are verified by `sh Scripts/install-app.sh` and
launching the app, never by reading the diff.

### Second brain

This repo is documented in the Obsidian vault at
`~/Library/Mobile Documents/com~apple~CloudDocs/Notes/ClercqIt/Projects/Cellar`. Code changes must be
written back there before a session ends (the `second-brain-sync` skill / Stop hook handles it).
