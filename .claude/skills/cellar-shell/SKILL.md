---
name: cellar-shell
description: Best practices for Cellar's shell scripts and macOS packaging. Use when editing Scripts/*.sh or anything about building the .app, the DMG, Info.plist, or release artifacts. Covers POSIX sh + set -eu, ShellCheck, mktemp/trap cleanup, the mandatory SDK-unset before swift build, Info.plist keys, signing/quarantine mechanics, the case-insensitive-FS zip-name trap, and the versionless DMG.
---

# Cellar — shell & packaging

The full guide is [`skills/shell-and-packaging.md`](../../../skills/shell-and-packaging.md); read it.
Key rules:

- **POSIX `sh`, `set -eu`, `cd "$(dirname "$0")/.."`,** quote every expansion, keep scripts
  idempotent, fail loudly on missing preconditions. `-u` is the one that stops a typo'd variable
  expanding to nothing inside an `rm -rf`. **The three current scripts are still `set -e` only** —
  adding `-u` is a real behaviour change and needs its own commit, with each script actually run.
- **Lint:** `shellcheck -s sh Scripts/*.sh`. Not installed here and not in CI — a gap, not a
  decision; run it if you have it.
- **Temp files:** `tmp=$(mktemp -d)` + `trap 'rm -rf "$tmp"' EXIT`, so a `set -e` abort still cleans
  up.
- **Signing:** artifacts are unsigned/unnotarised, but every arm64 Mach-O still carries an **ad-hoc**
  signature. What blocks a download is the `com.apple.quarantine` xattr, not the missing Developer
  ID. Prefer `ditto` over `cp -R` when assembling the bundle. If real signing ever lands, the release
  notes must stop telling people to right-click → Open.
- **Any script that runs `swift build` must `unset DEVELOPER_DIR SDKROOT` first** (Nix/devenv SDK
  breaks the build). `install-app.sh` / `package.sh` already do.
- **Info.plist** (kept in sync across `install-app.sh` and `package.sh`): `CFBundleName=Cellar`,
  `CFBundleGetInfoString` + `NSHumanReadableCopyright` (the description — don't drop them),
  `CFBundleIconFile=AppIcon`, stable identifier, min-system + hi-res keys.
- **Packaging traps (don't reintroduce):** zips are `Cellar-App-<v>.zip` / `Cellar-CLI-<v>.zip` to
  avoid a case-insensitive-FS collision; the DMG is versionless `Cellar.dmg` so the site's
  latest-download link resolves.
- **Never package** game files, bottles, runners, depots, D3DMetal, or logs.
- **Verify:** the script runs clean from a fresh checkout; the `.app` launches; PlistBuddy confirms
  the keys; naming matches `release.yml` and the site.

Before reporting done, run the **cellar-verifier** agent.
