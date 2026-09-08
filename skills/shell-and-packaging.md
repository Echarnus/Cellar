# Skill: Shell scripts & macOS packaging

Best practices for `Scripts/*.sh` and how Cellar assembles its `.app`, DMG, and release artifacts.
Read [`../AGENTS.md`](../AGENTS.md) first.

## Shell style

- **POSIX `sh`** — `#!/bin/sh`, and no bashisms (`[[ ]]`, arrays, `local` in the bash sense). These
  scripts also run on GitHub's runners; keep them portable.
- **`set -eu` at the top.** `-e` aborts on a failed command; **`-u` aborts on an unset variable**,
  which is the one that catches a typo'd `$DIST` silently expanding to nothing and an `rm -rf
  "$DIST/"` becoming `rm -rf /`. `pipefail` is bash-only — in POSIX `sh`, if you need a pipeline's
  exit status, restructure rather than assume.
  > **Current state:** `install-app.sh`, `package.sh` and `make-dmg.sh` are still `set -e` only. They
  > predate this rule. Adding `-u` is a real behaviour change (an unset optional variable becomes a
  > hard failure), so it must be done as its own change, with each script actually run afterwards —
  > not folded silently into an unrelated commit.
- `cd "$(dirname "$0")/.."` so a script runs from anywhere.
- Quote every expansion (`"$VAR"`). Absolute or `$0`-relative paths, never assume the CWD.
- Fail loudly with a clear message when a precondition is missing (e.g. `dist/Cellar.app` absent).
- Keep scripts idempotent — safe to re-run.

## Lint before you ship

**[ShellCheck](https://www.shellcheck.net) is the standard static analysis for shell**, and it is
what catches the unquoted-expansion and word-splitting bugs nobody spots by reading:

```sh
shellcheck -s sh Scripts/*.sh      # -s sh forces POSIX mode, matching our shebang
```

It is **not currently installed on this machine and not wired into CI** — that is a gap, not a
decision. If you are changing a script and have it available (`brew install shellcheck`, or add it to
the workspace's `devenv.nix`), run it; a clean run is cheap evidence. Adding it as a CI step belongs
with [`ci.md`](ci.md).

## Temporary files

Use `mktemp -d` and delete it from an `EXIT` trap, so a failure halfway through doesn't leave a
half-built bundle in `/tmp` or in `dist/`:

```sh
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
```

The `EXIT` trap fires on normal exit *and* on the abort that `set -e` triggers, which is precisely
why it beats a `rm -rf` at the end of the script. (`mktemp` is not in POSIX, but it is on every macOS
and every runner we use.)

## The SDK-unset rule (do not remove)

Any script that runs `swift build` must first:

```sh
unset DEVELOPER_DIR SDKROOT
```

A Nix/devenv shell exports these pointing at a non-macOS SDK; without unsetting, the build fails or
links the wrong SDK. `install-app.sh` and `package.sh` already do this — keep it.

## App bundle & Info.plist

`install-app.sh` (dev) and `package.sh` (release) generate `Cellar.app` with a hand-written
`Info.plist`. Keep these keys correct and in sync between the two scripts:

- `CFBundleName` = `Cellar` (drives the menu-bar app name and the About panel title).
- `CFBundleGetInfoString` + `NSHumanReadableCopyright` — the human-readable description and licence
  line. Don't drop them; the app looks unfinished without a description.
- `CFBundleIconFile` = `AppIcon` — the icon is built from `Resources/AppIcon.png` via
  `make-icon.swift` (regenerated if missing).
- `LSMinimumSystemVersion`, `NSHighResolutionCapable`, a stable `CFBundleIdentifier`.

Two scripts writing the same plist by hand is a drift hazard: if you add or change a key, change it
in **both**, and verify with `/usr/libexec/PlistBuddy -c "Print" dist/Cellar.app/Contents/Info.plist`.

## Signing, quarantine and Gatekeeper

Releases are **unsigned and unnotarised**, and the release notes tell users to right-click → Open.
Know the mechanics before you touch this:

- On Apple Silicon every Mach-O must carry **at least an ad-hoc signature** to execute at all; the
  toolchain applies one during the build. "Unsigned" here means *not Developer-ID signed*, which is a
  different thing from *no signature*.
- What actually blocks a downloaded app is the **`com.apple.quarantine`** extended attribute applied
  by the browser, not the missing signature per se. `xattr -dr com.apple.quarantine
  /Applications/Cellar.app` clears it; right-click → Open is the same escape hatch through the UI.
- Copying files with `ditto` preserves extended attributes and signatures; a naive `cp -R` of a
  signed bundle can invalidate it. Prefer `ditto` when assembling the bundle.
- If Developer-ID signing and notarisation ever land, they need a hardened runtime, `codesign
  --deep --options runtime`, `notarytool submit --wait` and `stapler staple` — **and the release
  notes must stop telling people to right-click.** Don't ship one without the other.

## Packaging traps (already solved — don't reintroduce)

- **Case-insensitive filesystem collision.** The zips are named `Cellar-App-<v>.zip` and
  `Cellar-CLI-<v>.zip` deliberately — a naive `Cellar-<v>.zip` / `cellar-<v>.zip` pair collides on
  macOS's case-insensitive FS and one silently overwrites the other.
- **Versionless DMG.** `make-dmg.sh` emits `dist/Cellar.dmg` (no version in the name) so the site's
  `releases/latest/download/Cellar.dmg` link always resolves. Don't add a version back.

## Never package

Game files, bottles, runners, downloaded depots, Apple's D3DMetal, or logs — see the hard rules in
[`../AGENTS.md`](../AGENTS.md). `.gitignore` enforces most of this; keep it that way.

## Verify

The changed script runs clean from a fresh checkout; `shellcheck -s sh` is quiet (if available); the
resulting `.app` launches; `Info.plist` carries the expected keys (`/usr/libexec/PlistBuddy -c
"Print" …`); release naming matches what `release.yml` and the site expect.

Related: [`swift.md`](swift.md) · [`ci.md`](ci.md) · [`web.md`](web.md) ·
[`../docs/RELEASING.md`](../docs/RELEASING.md)
