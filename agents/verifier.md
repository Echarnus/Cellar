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
- **Wine/runners/bottles** ([`../skills/wine-and-runners.md`](../skills/wine-and-runners.md)): no
  `/usr/bin/arch` wrapper; the environment is inherited *and* the caller's `WINE*`/`DYLD_*`/`D3DM*`/
  `MTL_*`/`GST_*`/`GRAPHICS_BACKEND` stripped; `WINEDLLOVERRIDES` **merged, not assigned over**;
  no bundled D3DMetal and nothing that circumvents DRM. Evidence that a **game actually started** —
  plus a clean process table afterwards (no orphan `wineserver`/`Agent.exe`). A clean build is not
  evidence about a runner.
- **Shell/packaging** ([`../skills/shell-and-packaging.md`](../skills/shell-and-packaging.md)):
  `set -eu` (or a stated reason it is still `set -e`) + SDK-unset present; temp dirs cleaned from an
  `EXIT` trap; Info.plist keys correct and in sync across both scripts; zip names don't collide on a
  case-insensitive FS; DMG stays versionless.
- **Python** ([`../skills/python.md`](../skills/python.md)): stdlib only; still Python-3.9-safe;
  every value interpolated into HTML is escaped; `open()` carries an explicit encoding; output stays
  deterministic.
- **CI** ([`../skills/ci.md`](../skills/ci.md)): least-privilege `permissions:` declared;
  third-party actions pinned to a commit SHA; no `${{ }}` interpolated into a `run:` block; trigger
  is `pull_request`, not `pull_request_target`. Verified by an actual run, not by reading YAML.
- **Profile** ([`../skills/profiles.md`](../skills/profiles.md)): required fields present;
  DRM/anti-cheat stated honestly and separately; `status` matches what was actually run, with
  tested-hardware `notes`. Parser-safe: scalars only, no `#` inside values, no duplicate key names
  across sections, `store`/`status` spelled from the known vocabulary.

**2b. UX/UI — for anything a player sees** ([`../skills/ux.md`](../skills/ux.md)):
one obvious next action with a plain sentence under it; empty / loading / first-run / busy / error
states all designed; light *and* dark; readable at the window's minimum width. **Honesty:** no ✓ for
a state Cellar cannot actually check (Battle.net sign-in), and any step the player must perform by
hand is announced before it happens (Battle.net's installer). Store identity carried by position +
mark + word, never colour alone; store marks drawn in code, never bundled logo files. Icon-only
controls have both `.accessibilityLabel` and `.help`. **Evidence: a screenshot of the changed screen
from a launched build** — a diff is not evidence about an interface.

**3. It enforces the hard project rules** ([`../AGENTS.md`](../AGENTS.md) → *Hard project rules*):
no bundled D3DMetal or game files; no DRM/anti-cheat circumvention; nothing that should be gitignored
is being committed; commit messages carry no attribution trailers.

## Output

A verdict — **PASS** or **FAIL** — with, for each failure: the file/line, the demand it misses, and
the concrete failure scenario. It never rubber-stamps: if evidence of actual execution is missing, it
reports the change as unverified rather than assuming success.
