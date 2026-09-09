# Branching & releasing

Cellar uses **trunk-based development** with tagged releases. Small project, one maintainer, fast
iteration — GitFlow's long-lived branches would be overhead with no payoff.

## Branches

- **`main`** is always releasable. CI (`.github/workflows/ci.yml`) builds, tests and self-tests every
  push and PR on a macOS runner, so `main` stays green.
- **Commit straight to `main`.** With one maintainer, a PR per change is review nobody performs plus
  a branch to clean up afterwards. What keeps `main` releasable is the verification ladder in
  [`AGENTS.md`](../AGENTS.md) — run it, then push. Agents included: they do not need to ask.
- **Branch when it buys something**: work spanning several sessions, a change worth reading as a diff
  first, or one you want CI to vet before it lands. Then PR → merge. That is the exception now, not
  the default.
- No `develop` branch. No release branches — a release is just a tag on `main`.
- **Never force-push or rewrite published history.**

## Versioning

[Semantic Versioning](https://semver.org): `vMAJOR.MINOR.PATCH`.

- **PATCH** — fixes, profile tweaks, a new game profile.
- **MINOR** — new user-facing capability (a command, the GUI, a runner, the depot path).
- **MAJOR** — a breaking change to the CLI, profile schema, or on-disk layout.

Pre-1.0 (where we are): treat MINOR as "notable" and PATCH as "small"; breaking changes are allowed
in MINOR and called out in the release notes.

## Cutting a release

```sh
git switch main && git pull
git tag v0.1.0            # annotate if you like: git tag -a v0.1.0 -m "…"
git push origin v0.1.0
```

The tag triggers `.github/workflows/release.yml`, which on a macOS runner:

1. builds `cellar` + `CellarApp` in release,
2. runs `Scripts/package.sh <version>` to assemble `Cellar.app` (with icon) and the CLI,
3. publishes a **GitHub Release** with `Cellar-App-<v>.zip` and `Cellar-CLI-<v>.zip` plus
   auto-generated notes.

`workflow_dispatch` builds the same artifacts on demand (uploaded as workflow artifacts, no Release).

Artifacts are **unsigned / unnotarised** — the release notes tell users to clear the quarantine flag
(`xattr -dr com.apple.quarantine Cellar.app`) or right-click → Open. Signing/notarisation is a later
step once there's a Developer ID.

## Supported-games site

`.github/workflows/pages.yml` regenerates the [supported-games page](https://echarnus.github.io/Cellar/)
from `profiles/*.toml` (via `Scripts/gen-site.py`) and deploys it to GitHub Pages on every push to
`main` that touches profiles or the generator. Enable it once under **Settings → Pages → Source:
GitHub Actions**.
