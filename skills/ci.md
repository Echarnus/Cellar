# Skill: CI/CD — GitHub Actions

Best practices for the three workflows in `.github/workflows/`. Portable guide; Claude's
auto-discovered copy is `.claude/skills/cellar-ci/SKILL.md`. Read [`../AGENTS.md`](../AGENTS.md) and
[`../docs/RELEASING.md`](../docs/RELEASING.md) first.

## What runs, and when

| Workflow | Trigger | Does |
|---|---|---|
| `ci.yml` | push to `main`, every PR, manual | Release build → `cellar selftest` → generate the site as a sanity check. On `macos-15`. |
| `release.yml` | a `v*` tag, or manual with a version | `package.sh` (app + CLI zips) → `make-dmg.sh` → upload artifacts → publish a GitHub Release. |
| `pages.yml` | push to `main` touching `profiles/**` or the generator | Regenerates the site and deploys to GitHub Pages. |

The runners are **pinned to `macos-15`**, not `macos-latest`. Keep it that way — `-latest` moves and
takes the Xcode/Swift toolchain with it, which is exactly the variable this project cannot afford to
have drift silently. Bumping it is a deliberate change, verified by a green build.

## Security: the four things to get right

CI is the softest target in any repo — it holds a write-capable token and runs other people's code.

1. **Declare least-privilege `permissions:` on every workflow.** A workflow with no `permissions:`
   block inherits the repository default, which is frequently read *and write* for `GITHUB_TOKEN`.
   `release.yml` correctly declares `contents: write`; `pages.yml` correctly declares
   `contents: read` + `pages: write` + `id-token: write`. **`ci.yml` declares nothing** — it only
   builds, so it should say `permissions: contents: read`. Elevate per-job, never globally.
2. **Pin third-party actions to a full commit SHA, not a tag.** Tags are mutable: an attacker who
   gets push access can move `v2` to malicious code and every pipeline picks it up on the next run.
   This is not theoretical — in March 2026 the `trivy-action` tags were force-pushed en masse to
   exfiltrate secrets from every repo that ran them. **`softprops/action-gh-release@v2` in
   `release.yml` is our third-party action and the one that matters most**, because it runs in the
   job that holds `contents: write`. Pin it as
   `softprops/action-gh-release@<40-char-sha>  # v2.x.y`, keeping the version in a comment so the
   next person knows what they are updating. GitHub's own `actions/*` are lower risk but pinning them
   costs nothing.
3. **Never interpolate `${{ … }}` directly into a `run:` block.** The expression is substituted into
   the shell *before* it runs, so any quote or `;` in the value becomes code. `release.yml` does this
   with `github.event.inputs.version` and with `steps.v.outputs.version`. Only someone who can
   dispatch the workflow controls that input today, so this is a hardening fix rather than an open
   hole — but it is the exact pattern that becomes a vulnerability the moment a value comes from a
   PR title, branch name or issue body. Pass through the environment instead:

   ```yaml
   - name: Package
     env:
       VERSION: ${{ steps.v.outputs.version }}
     run: Scripts/package.sh "$VERSION"
   ```

4. **Keep the trigger `pull_request`, never `pull_request_target`.** `pull_request` runs fork code
   with a read-only token and no secrets, which is correct for a public repo. `pull_request_target`
   runs with the *base* repo's secrets and write token — combining it with a checkout of the PR head
   hands the repository to anyone who can open a pull request.

## Reliability

- **Set `timeout-minutes` on every job.** The default is 6 hours; a hung `swift build` or a
  `wineserver` that never exits will happily burn all of it. Ten to twenty minutes is generous here.
- **`concurrency` is right for CI, wrong for deploys.** `ci.yml` cancelling superseded runs of the
  same ref is exactly what you want. `pages.yml` currently sets `cancel-in-progress: true` on the
  `pages` group — for a *deployment* that means a half-finished deploy can be cancelled mid-flight.
  GitHub's own Pages guidance is `cancel-in-progress: false`: let the running deploy finish and queue
  the next.
- **`release.yml` has no `concurrency` group.** Two tags pushed close together race on the same
  release artifacts. A group keyed on the tag is cheap insurance.

## What CI does *not* check (and should)

Be honest about the gate's real strength — it is "it compiled and a smoke test exited 0":

- **`swift test` runs nothing** — there is no test target ([`swift.md`](swift.md)). `cellar selftest`
  is a smoke test inside the CLI, not a suite.
- **No `shellcheck`** on `Scripts/*.sh` ([`shell-and-packaging.md`](shell-and-packaging.md)).
- **No lint** on `gen-site.py` ([`python.md`](python.md)).
- **The site is generated but never inspected** — CI proves the generator doesn't crash, not that the
  page is correct. Only `tomllib` is exercised there, never the 3.9 fallback parser that this machine
  actually uses ([`profiles.md`](profiles.md)).
- **Nothing launches the app.** GUI and Wine behaviour are verified by a human on hardware; CI cannot
  and should not pretend otherwise.

Adding any of these is a welcome change — just add them as a real gate, not an `|| true` step.

## Releases

The release flow is documented in [`../docs/RELEASING.md`](../docs/RELEASING.md); the packaging rules
(zip naming, versionless DMG, Info.plist) are in
[`shell-and-packaging.md`](shell-and-packaging.md). Two CI-specific points:

- **Artifacts are unsigned and unnotarised**, and the release body tells users to right-click → Open.
  If signing is ever added, its certificate and password are repository **secrets**, and secrets must
  never be exposed to a `pull_request` run.
- **The release body is user-facing copy.** It is held to the same bar as the app's text
  ([`ux.md`](ux.md)) — say what happens, name what the player will see, no jargon.

## Verify

A workflow change is verified by **a run**, not by reading YAML:

1. Push the branch and let `ci.yml` go green (it runs on every PR).
2. For `release.yml`, use the `workflow_dispatch` path with a throwaway version before trusting a
   tag — it builds and uploads artifacts without publishing a Release (that step is gated on
   `github.event_name == 'push'`).
3. For `pages.yml`, confirm the deployed site shows the profile you changed.
4. After changing permissions or pins, re-read the run log: a token that is now too narrow fails
   loudly at the step that needed it, which is the outcome you want to see once.

Related: [`shell-and-packaging.md`](shell-and-packaging.md) · [`python.md`](python.md) ·
[`web.md`](web.md) · [`../docs/RELEASING.md`](../docs/RELEASING.md)
