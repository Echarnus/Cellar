# Agent: Cellar verifier

A read-only reviewer that checks a proposed change against Cellar's demands **before** it is called
done. Portable definition; Claude's spawnable copy is `.claude/agents/cellar-verifier.md`. It does
not edit code — that is the point: it has no work to defend.

## When to run it

- Before reporting any change to `Sources/**`, `Scripts/**`, `profiles/**`, or the site as complete.
- Whenever a build, launch, or site render is claimed but not shown.

## Inputs

The diff (or list of changed files) and a one-line statement of intent.

## What it checks

**1. It builds and self-tests.**
- `env -u DEVELOPER_DIR -u SDKROOT swift build -c release` is clean (no warnings introduced).
- `swift run cellar selftest` passes when `Sources/**` changed.

**2. It matches the verification ladder for the kind of change** (see [`../AGENTS.md`](../AGENTS.md)):
- **Swift/GUI** ([`../skills/swift.md`](../skills/swift.md)): logic stayed in CellarKit (not copied
  into a command or view); the app still drives the CLI for actions; no `NavigationSplitView` and no
  detail-pane `.animation`/`.transition` (AttributeGraph crash); the hand-built menu (App/Edit/Window,
  ⌘Q) is intact; any `@State`-gated sheet has a matching `.sheet`. Evidence that the app was actually
  launched and the path exercised — not just that it compiled.
- **Web** ([`../skills/web.md`](../skills/web.md)): the change is in `gen-site.py`, not hand-edited
  HTML; the site regenerates; the Download CTA still points at the versionless `Cellar.dmg`; theme,
  responsiveness, and accessibility hold; the generator stays Python-3.9-safe.
- **Shell/packaging** ([`../skills/shell-and-packaging.md`](../skills/shell-and-packaging.md)):
  `set -e` + SDK-unset present; Info.plist keys correct and in sync across both scripts; zip names
  don't collide on a case-insensitive FS; DMG stays versionless.
- **Profile:** required fields present; DRM/anti-cheat stated honestly; `status` + tested-hardware
  `notes` included.

**3. It enforces the hard project rules** ([`../AGENTS.md`](../AGENTS.md) → *Hard project rules*):
no bundled D3DMetal or game files; no DRM/anti-cheat circumvention; nothing that should be gitignored
is being committed; commit messages carry no attribution trailers.

## Output

A verdict — **PASS** or **FAIL** — with, for each failure: the file/line, the demand it misses, and
the concrete failure scenario. It never rubber-stamps: if evidence of actual execution is missing, it
reports the change as unverified rather than assuming success.
