---
name: cellar-ci
description: Best practices for Cellar's GitHub Actions workflows (ci.yml, release.yml, pages.yml). Use when editing anything under .github/workflows, changing how the project builds, releases or deploys the site, or wiring a new check into CI. Covers least-privilege permissions, pinning third-party actions to commit SHAs, avoiding expression interpolation in run blocks, pull_request vs pull_request_target, job timeouts and deploy concurrency, and an honest account of what CI does not check.
---

# Cellar — CI/CD

The full guide is [`skills/ci.md`](../../../skills/ci.md); read it. Key rules:

- **Delivery flow:** issue → branch → PR with `Closes #N` → auto-merge (squash) once the required
  checks pass → `v*` tag → `release.yml` publishes with notes built from the closed issues
  (`Scripts/release-notes.py`). Full table in `docs/RELEASING.md` → *Checks*. Runners are pinned to
  `macos-15` / `ubuntu-24.04`, not `-latest`.
- **Least-privilege `permissions:`**: `contents: read` at the top of every workflow, elevated per
  job. Only the release publish job holds `contents: write`.
- **Pin every action to a full commit SHA** with the version in a trailing comment; Dependabot
  updates both. Downloaded tools are fetched by version and checked against a SHA-256.
- **Never interpolate `${{ … }}` into a `run:` block.** Pass it via `env:` and reference `"$VAR"`.
- **Keep the trigger `pull_request`, never `pull_request_target`.**
- **Set `timeout-minutes`** on every job. Deploys and releases use `cancel-in-progress: false`.
- **Required check names are an interface** — `.github/rulesets/main.json` lists them; rename a job
  and update the ruleset in the same PR.
- **Release secrets live in the `release` environment**, never in repository secrets.
- **Verify by a run**, not by reading YAML — `workflow_dispatch` the release path with a throwaway
  version before trusting a tag.

Related: [`cellar-shell`](../cellar-shell/SKILL.md) · [`cellar-python`](../cellar-python/SKILL.md).
