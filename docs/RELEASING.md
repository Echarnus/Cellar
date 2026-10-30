# Branching & releasing

Cellar uses **trunk-based development**: short-lived branches, one pull request per issue, merged into
`main` as soon as the checks are green, and releases cut as tags on `main`. No `develop` branch, no
release branches.

## Issues

Every piece of work starts as an issue, because the issues are what a release's notes are made of.

- **Title it for a player.** "Frontier Workshop can't be reached from inside Planet Coaster" reads
  well in release notes; "fix winhttp override" does not.
- **Label it.** The label decides the section it appears under in the release notes. The set lives
  in [`.github/labels.yml`](../.github/labels.yml) and is applied by the Labels workflow.

  | Label | Release-notes section |
  |---|---|
  | `breaking-change` | Breaking changes |
  | `security` | Security |
  | `bug` | Fixes |
  | `enhancement` | New and improved |
  | `performance` | Performance |
  | `ux` | Look and feel |
  | `compatibility` | Compatibility |
  | `networking` | Online play |
  | `game-profile` | Games |
  | `legal` | Licences and credits |
  | `documentation` | Documentation |
  | `ci` | Delivery |
  | `dependencies` | Dependencies |
  | `skip-changelog` | left out |

  An issue with several labels lands in the first matching section in that order.
- **Close it as "not planned" or "duplicate"** when it won't be done. Only issues closed as
  completed appear in the notes.

## Pull requests

1. Branch from `main` (`fix/dock-name`, `feat/updater`, anything readable).
2. Climb the verification ladder in [`AGENTS.md`](../AGENTS.md). CI is a floor, not a substitute: it
   cannot launch the app or a game.
3. Open a PR from the template. Its body says **`Closes #N`**, which is what links it to the
   issue and closes the issue when it merges.
4. **Turn on auto-merge (squash).** The PR merges by itself once every required check is green.

### Why auto-merge and not auto-approve

GitHub never lets the author of a pull request approve it, and Claude opens PRs as the maintainer.
An approving review from a second bot account would be a rubber stamp: it would look like review
without being one, and it is one more credential that can write to `main`. So the ruleset requires
**zero** approvals and makes the checks the gate instead: build, tests, self-test, lint, CodeQL and
dependency review must all pass on an up-to-date branch, and every review conversation must be
resolved. What this gives up is a second human pair of eyes; with one maintainer that was never
there. If a contributor joins, raise `required_approving_review_count` to 1 and turn on
`require_code_owner_review` — CODEOWNERS is already in place.

Dependabot's patch and minor updates auto-merge the same way (`dependabot-auto-merge.yml`); a major
update waits for a person.

## Checks

| Workflow | Runs on | Does |
|---|---|---|
| `ci.yml` | every PR, `main`, merge queue | On macOS 15 and 26: release build, test suite, Dock shim, `cellar selftest`, site generation; actionlint, ShellCheck, Python compile. |
| `codeql.yml` | every PR, `main`, weekly | CodeQL security-and-quality queries for Swift, Python and the workflows. |
| `dependency-review.yml` | every PR | Blocks a new dependency with a known vulnerability or a licence that can't ship under GPL-3.0. |
| `scorecard.yml` | `main`, weekly | OpenSSF Scorecard for the repository's supply-chain practices. |
| `labels.yml` | `main` when the labels change | Applies `.github/labels.yml`. |
| `pages.yml` | `main` when profiles change | Publishes the supported-games site. |
| `release.yml` | a `v*` tag | Builds, writes the notes, publishes the release. |

Every workflow declares least-privilege `permissions:`, pins every action to a commit SHA (Dependabot
keeps them current) and passes `${{ }}` values through `env:`, never into a `run:` line. See
[`skills/ci.md`](../skills/ci.md).

## Versioning

[Semantic Versioning](https://semver.org): `vMAJOR.MINOR.PATCH`.

- **PATCH**: fixes, profile tweaks, a new game profile.
- **MINOR**: new user-facing capability (a command, the GUI, a runner, the depot path).
- **MAJOR**: a breaking change to the CLI, profile schema, or on-disk layout.

Pre-1.0 (where we are): treat MINOR as "notable" and PATCH as "small"; breaking changes are allowed
in MINOR and called out in the release notes (label the issue `breaking-change`).

A suffix makes a pre-release: `v0.5.0-beta.1` is published as one, and the in-app updater and
`releases/latest` ignore it.

## Cutting a release

```sh
git switch main && git pull
git tag -a v0.4.0 -m "Cellar 0.4.0"
git push origin v0.4.0
```

The tag runs [`release.yml`](../.github/workflows/release.yml):

1. **Build** (macOS, read-only token): runs the test suite, `Scripts/package.sh` and
   `Scripts/make-dmg.sh`, and writes `SHA256SUMS.txt`.
2. **Publish** (the `release` environment, the only job with write access):
   - writes the notes with `Scripts/release-notes.py`: every issue closed by a PR merged since the
     previous tag, plus any issue closed as completed in that window, grouped by label, then
     GitHub's list of merged PRs and the install instructions;
   - signs the app zip and writes `appcast.xml` for the in-app updater, once
     `Resources/sparkle-public-key` and the `SPARKLE_ED_PRIVATE_KEY` secret exist;
   - attests build provenance for every download;
   - publishes the GitHub Release with the DMG, both zips, the checksums and the feed.

To preview the notes before tagging: `GH_TOKEN=… python3 Scripts/release-notes.py --repo
Echarnus/Cellar --tag HEAD --out /tmp/notes.md`. `workflow_dispatch` builds the downloads for any
version without publishing anything.

Artifacts are **ad-hoc signed but not notarised**. `package.sh` seals the bundle with
`codesign --sign -`, because an unsealed bundle (an Info.plist added after the linker signed the
binary) is reported as "damaged" by macOS 15+ Gatekeeper with no way past it. The release notes tell
users to allow it once under **System Settings → Privacy & Security → Open Anyway**; right-click →
Open stopped bypassing Gatekeeper in macOS 15. Developer-ID signing and notarisation are a later step
once there's a Developer ID (it needs the hardened runtime, `notarytool submit --wait` and
`stapler staple`); the certificate then goes into the `release` environment's secrets, never into
repository secrets a PR could reach.

## One-time repository setup

These are settings, not files, so the maintainer applies them once:

1. **Settings → General → Pull Requests**: allow squash merging only, tick *Allow auto-merge* and
   *Automatically delete head branches*.
2. **Settings → Rules → Rulesets → New ruleset → Import**: import
   [`.github/rulesets/main.json`](../.github/rulesets/main.json) (protects `main`) and
   [`.github/rulesets/tags.json`](../.github/rulesets/tags.json) (release tags can't be moved or
   deleted).
3. **Settings → Environments → release**: add a deployment rule allowing only tags matching `v*`,
   `sh Scripts/sparkle-keys.sh` creates the environment and stores `SPARKLE_ED_PRIVATE_KEY` in it.
4. **Settings → Code security**: turn on Dependabot alerts and security updates, secret scanning
   and push protection, and private vulnerability reporting.
5. **Settings → Actions → General**: workflow permissions *Read repository contents*, and untick
   *Allow GitHub Actions to create and approve pull requests*.

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
- The private half lives in the maintainer's login keychain and in the `SPARKLE_ED_PRIVATE_KEY`
  secret of the `release` environment (not a repository secret, so no PR run can read it), and
  nowhere else. `Scripts/make-appcast.sh <version> <notes.md>` signs the
  zip with it, checks it matches the public key in the repo, and writes `dist/appcast.xml`; the
  release workflow uploads that next to the zip.
- **Set-up, once:** run `sh Scripts/sparkle-keys.sh` on the Mac, then commit
  `Resources/sparkle-public-key`. It reuses an existing key rather than making a new one.
- **Never rotate or lose the key casually.** Every installed copy accepts only updates signed by the
  key it shipped with; a new key means every player downloads the next version by hand.

Each `Cellar.app` carries its own `cellar` CLI (`Contents/MacOS/cellar`), which the app prefers over
one on PATH, so an update replaces the app and the engine together. `Scripts/bundle-app.sh` puts the
CLI and `Sparkle.framework` into the bundle before the ad-hoc seal covers them; Sparkle refuses an
update whose bundle signature is present but broken.

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
