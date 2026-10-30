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

Artifacts are **not Developer-ID signed or notarised** (the app is ad-hoc signed, which is what lets
Sparkle verify an update's bundle) — the release notes tell users to clear the quarantine flag
(`xattr -dr com.apple.quarantine Cellar.app`) or right-click → Open. Signing/notarisation is a later
step once there's a Developer ID.

## In-app updates (Sparkle)

Cellar updates itself with [Sparkle 2](https://sparkle-project.org). **Cellar › Check for Updates…**
(and Settings › Updates) reads the feed at
`https://github.com/Echarnus/Cellar/releases/latest/download/appcast.xml` — the `appcast.xml` asset
of the newest release — shows the release notes, and installs the new `Cellar-App-<v>.zip` when the
player says so. Automatic checks are opt-in: Sparkle asks on the second launch, and Settings has the
switch.

The chain of trust is an **EdDSA key**, not Apple code signing (there is no Developer ID yet):

- `Resources/sparkle-public-key` holds the public half. `Scripts/package.sh` writes it into
  Info.plist as `SUPublicEDKey`, with `SUFeedURL`, and only when the file exists — before that, a
  release simply ships with updates switched off. `Scripts/install-app.sh` never writes either, so a
  build from source never replaces itself with a release.
- The private half lives in the maintainer's login keychain and in the repository secret
  `SPARKLE_ED_PRIVATE_KEY`, and nowhere else. `Scripts/make-appcast.sh <version> <notes.md>` signs the
  zip with it, checks it matches the public key in the repo, and writes `dist/appcast.xml`; the
  release workflow uploads that next to the zip.
- **Set-up, once:** run `sh Scripts/sparkle-keys.sh` on the Mac, then commit
  `Resources/sparkle-public-key`. It reuses an existing key rather than making a new one.
- **Never rotate or lose the key casually.** Every installed copy accepts only updates signed by the
  key it shipped with; a new key means every player downloads the next version by hand.

Each `Cellar.app` carries its own `cellar` CLI (`Contents/MacOS/cellar`), which the app prefers over
one on PATH, so an update replaces the app and the engine together. `Scripts/bundle-app.sh` puts the
CLI and `Sparkle.framework` into the bundle and ad-hoc signs it; Sparkle refuses an update whose
bundle signature is present but broken.

Players on a release from before the updater (0.2.x and earlier) have to download one version by
hand; after that, updates arrive in the app.

## Supported-games site

`.github/workflows/pages.yml` regenerates the [supported-games page](https://echarnus.github.io/Cellar/)
from `profiles/*.toml` (via `Scripts/gen-site.py`) and deploys it to GitHub Pages on every push to
`main` that touches profiles or the generator. Enable it once under **Settings → Pages → Source:
GitHub Actions**.

The generator writes two pages: `index.html` (the games grid) and `faq.html` (the
[questions &amp; answers](https://echarnus.github.io/Cellar/faq.html) page, which the app links to
from **Settings → Help**). The FAQ's prose lives in `FAQ_SECTIONS` in `Scripts/gen-site.py` — it
makes factual claims about how Cellar behaves, so it changes when the behaviour does.
