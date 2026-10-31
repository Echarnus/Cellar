# Skill: CI/CD — GitHub Actions

Best practices for the three workflows in `.github/workflows/`. Portable guide; Claude's
auto-discovered copy is `.claude/skills/cellar-ci/SKILL.md`. Read [`../AGENTS.md`](../AGENTS.md) and
[`../docs/RELEASING.md`](../docs/RELEASING.md) first.

## What runs, and when

The full table, and the delivery flow it serves (issue → PR → auto-merge → tag → release), is in
[`../docs/RELEASING.md`](../docs/RELEASING.md) → *Checks*. In short: `ci.yml` (build, tests,
self-test, lint), `codeql.yml`, `dependency-review.yml` and `scorecard.yml` guard every PR;
`release.yml` turns a `v*` tag into a GitHub Release whose notes come from the issues it closed;
`pages.yml` publishes the site; `labels.yml` applies `.github/labels.yml`;
`dependabot-auto-merge.yml` merges patch and minor dependency bumps once they are green.

The runners are **pinned to `xcode-27`** (macOS 27, Cellar's minimum) and `ubuntu-24.04`, not `-latest`. Keep it that way —
`-latest` moves and takes the Xcode/Swift toolchain with it, which is exactly the variable this
project cannot afford to have drift silently. Bumping it is a deliberate change, verified by a
green build.

## Security: the four things to get right

CI is the softest target in any repo — it holds a write-capable token and runs other people's code.

1. **Declare least-privilege `permissions:` on every workflow.** A workflow with no `permissions:`
   block inherits the repository default, which is frequently read *and write* for `GITHUB_TOKEN`.
   Every workflow sets `contents: read` at the top and elevates per job: only `release.yml`'s
   publish job holds `contents: write`, only `pages.yml`'s deploy job holds `pages: write`.
2. **Pin third-party actions to a full commit SHA, not a tag.** Tags are mutable: an attacker who
   gets push access can move `v2` to malicious code and every pipeline picks it up on the next run.
   This is not theoretical — in March 2026 the `trivy-action` tags were force-pushed en masse to
   exfiltrate secrets from every repo that ran them. Every action here is pinned as
   `owner/action@<40-char-sha> # vX.Y.Z`, and Dependabot moves SHA and comment together. The release
   job publishes with the runner's own `gh` rather than a third-party action, so nothing outside
   GitHub runs while `contents: write` is held. Tools a workflow downloads (actionlint) are fetched
   by exact version and checked against a SHA-256.
3. **Never interpolate `${{ … }}` directly into a `run:` block.** The expression is substituted into
   the shell *before* it runs, so any quote or `;` in the value becomes code — the exact pattern
   that becomes a vulnerability the moment a value comes from a PR title, branch name or issue body.
   None of the workflows do it; keep it that way. Pass through the environment instead:

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
  `wineserver` that never exits will happily burn all of it.
- **`concurrency` is right for CI, wrong for deploys.** CI cancels superseded runs of a ref; Pages
  and Release use `cancel-in-progress: false`, so a half-finished deploy or release is never cut off.
- **Required check names are an interface.** `.github/rulesets/main.json` requires the jobs by name
  (`Build & self-test (macos-27)`, `Lint (workflows, shell, Python)`, `Analyze (swift)`, …). Renaming a
  job without updating the ruleset leaves every PR waiting for a check that will never report.

## What CI does *not* check (and should)

Be honest about the gate's real strength — it is "it compiled and a smoke test exited 0":

- **The Wine tiers never run in CI** — `Scripts/test.sh` runs the hermetic suite; `--integration`
  and `--steam` are local rungs.
- **ShellCheck runs at warning severity**, so style notes (`SC2012` and the like) do not fail it.
- **Python is only compiled**, not linted ([`python.md`](python.md)).
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

- **Artifacts are ad-hoc signed and unnotarised**, and the release notes tell users to allow Cellar
  under System Settings → Privacy & Security → Open Anyway.
  Release secrets (the update-signing key now, a Developer ID later) live in the `release`
  **environment**, which only the tag-triggered publish job enters — never in repository secrets a
  `pull_request` run could reach.
- **The release notes are user-facing copy.** They are written by `Scripts/release-notes.py` from
  issue titles, so an issue title is release-note copy too. It is held to the same bar as the app's text
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
