---
name: cellar-ci
description: Best practices for Cellar's GitHub Actions workflows (ci.yml, release.yml, pages.yml). Use when editing anything under .github/workflows, changing how the project builds, releases or deploys the site, or wiring a new check into CI. Covers least-privilege permissions, pinning third-party actions to commit SHAs, avoiding expression interpolation in run blocks, pull_request vs pull_request_target, job timeouts and deploy concurrency, and an honest account of what CI does not check.
---

# Cellar — CI/CD

The full guide is [`skills/ci.md`](../../../skills/ci.md); read it. Key rules:

- **Three workflows:** `ci.yml` (build + `cellar selftest` + generate the site, every PR),
  `release.yml` (tag → zips + DMG + GitHub Release), `pages.yml` (profiles/generator → Pages).
  Runners are pinned to `macos-15`, not `-latest` — keep it; `-latest` moves the toolchain.
- **Declare least-privilege `permissions:` on every workflow.** `ci.yml` declares none, so it
  inherits the repo default (often write) for a job that only builds — it should say
  `contents: read`. `release.yml` (`contents: write`) and `pages.yml` are already correct.
- **Pin third-party actions to a full commit SHA**, keeping the version in a trailing comment. Tags
  are mutable and have been mass-force-pushed in real supply-chain attacks.
  `softprops/action-gh-release@v2` matters most — it runs in the job holding `contents: write`.
- **Never interpolate `${{ … }}` into a `run:` block.** Pass it via `env:` and reference `"$VAR"`.
  `release.yml` currently interpolates the dispatch input and a step output directly.
- **Keep the trigger `pull_request`, never `pull_request_target`** — the latter runs with the base
  repo's secrets and write token.
- **Set `timeout-minutes`** (default is 6 hours). CI's `cancel-in-progress: true` is right; for the
  Pages *deploy* it should be `false` so a running deploy is not cancelled mid-flight.
  `release.yml` has no concurrency group at all.
- **Be honest about the gate:** `swift test` runs nothing (no test target), no shellcheck, no Python
  lint, the site is generated but never inspected, and only `tomllib` is exercised — never the 3.9
  fallback this machine uses. Adding any of these is welcome, as a real gate, not `|| true`.
- **Verify by a run**, not by reading YAML — `workflow_dispatch` the release path with a throwaway
  version before trusting a tag.

Related: [`cellar-shell`](../cellar-shell/SKILL.md) · [`cellar-python`](../cellar-python/SKILL.md).
