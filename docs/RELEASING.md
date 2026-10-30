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

Artifacts are **ad-hoc signed but not notarised** until a Developer ID is supplied (below).
`package.sh` seals the bundle through `Scripts/sign-app.sh`, because an unsealed bundle (an
Info.plist added after the linker signed the binary) is reported as "damaged" by macOS 15+ Gatekeeper
with no way past it. The release notes tell users to allow it once under **System Settings → Privacy
& Security → Open Anyway**; right-click → Open stopped bypassing Gatekeeper in macOS 15.

## The installer DMG

`Scripts/make-dmg.sh` turns `dist/Cellar.app` into `dist/Cellar.dmg`, the download the site links
to. Opened, it is the window every Mac installer has: a background drawn by
`Scripts/make-dmg-background.swift` (no image files in the repo), Cellar on the left, an arrow, the
Applications folder on the right, and a *Licence and Read Me* folder underneath. Cellar's icon is the
volume icon. Finder lays the window out through AppleScript, which needs a logged-in Finder — the
GitHub macOS runners have one. If it ever fails the DMG is still built (plain Finder look) and the
job shows a warning; `CELLAR_DMG_STRICT=1` turns that into a failure.

What happens after the drag is the app's job, not the DMG's:

- **Started from the disk image?** Cellar offers to move itself into Applications and reopens from
  there (`InstallLocation`), so it does not vanish on eject and the updater can replace it.
- **First launch** starts `cellar prepare` in the background: the Wine runner (with D3DMetal),
  DepotDownloader and the shared Windows Steam client with its first update — a few GB, fetched from
  their publishers on the player's Mac, never bundled. The first Install is then just the game. A
  game set up meanwhile waits for it (`SetupLock`). Settings › Advanced can switch it off.
- **Uninstalling** is *Cellar › Uninstall Cellar…* (or `cellar uninstall-cellar`): the app, the CLI,
  bottles, runners, the Steam client and its games, caches, preferences and generated launchers.
  Save games are copied to `~/Documents/Cellar Saved Games/<date>` first unless the player unticks
  it; if that copy fails, nothing is deleted.

## Developer ID signing and notarisation

Everything is in place except the paid Apple Developer account. Until its secrets exist, releases
stay ad-hoc signed and nothing below runs.

| Script | Does | Needs |
|---|---|---|
| `Scripts/sign-app.sh <app>` | Signs inside-out (Sparkle's XPC services and helpers, the bundled CLI, the Dock shim, then the app). Ad-hoc by default; with an identity, hardened runtime + secure timestamp. | `CELLAR_SIGN_IDENTITY` (optional) |
| `Scripts/notarize.sh <app\|dmg>` | Submits to Apple's notary service, waits, staples the ticket. Prints Apple's log on rejection. A no-op without credentials. | `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY` |
| `Scripts/import-signing-identity.sh` | CI only: imports the certificate into a throwaway keychain and exports `CELLAR_SIGN_IDENTITY`. | `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD` |

`package.sh` signs and (when it can) notarises the app before zipping it, so the zip the updater
ships is trusted on its own; `make-dmg.sh` then signs and notarises the DMG.

**To switch it on (Kenneth, once):**

1. Join the Apple Developer Program, then in Xcode › Settings › Accounts › Manage Certificates
   create a **Developer ID Application** certificate. Export it from Keychain Access as a `.p12`
   with a password.
2. In App Store Connect › Users and Access › Integrations › App Store Connect API, create a key with
   the *Developer* role. Note its Key ID and the Issuer ID, and download the `.p8` (once only).
3. Add these as secrets of the `release` environment (Settings › Environments › release):
   `DEVELOPER_ID_P12` (`base64 -i cert.p12 | pbcopy`), `DEVELOPER_ID_P12_PASSWORD`,
   `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY` (the `.p8` file's contents).
4. In the release workflow's build job, before *Package*, add:

   ```yaml
   - name: Signing identity
     env:
       DEVELOPER_ID_P12: ${{ secrets.DEVELOPER_ID_P12 }}
       DEVELOPER_ID_P12_PASSWORD: ${{ secrets.DEVELOPER_ID_P12_PASSWORD }}
     run: |
       eval "$(sh Scripts/import-signing-identity.sh)"
       echo "CELLAR_SIGN_IDENTITY=${CELLAR_SIGN_IDENTITY:--}" >> "$GITHUB_ENV"
   ```

   and pass `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` and `NOTARY_KEY` as `env:` to the *Package* and
   *Build installer DMG* steps. The build job then needs `environment: release` to read them.
5. **Change the release notes in the same commit:** a notarised Cellar opens with a double-click,
   so "Open Anyway" must stop being part of the instructions (also in `make-dmg.sh`'s *Read Me*).

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
