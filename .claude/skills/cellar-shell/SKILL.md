---
name: cellar-shell
description: Best practices for Cellar's shell scripts and macOS packaging. Use when editing Scripts/*.sh or anything about building the .app, the DMG, Info.plist, or release artifacts. Covers POSIX sh + set -e, the mandatory SDK-unset before swift build, Info.plist keys, the case-insensitive-FS zip-name trap, and the versionless DMG.
---

# Cellar — shell & packaging

The full guide is [`skills/shell-and-packaging.md`](../../../skills/shell-and-packaging.md); read it.
Key rules:

- **POSIX `sh`, `set -e`, `cd "$(dirname "$0")/.."`,** quote every expansion, keep scripts
  idempotent, fail loudly on missing preconditions.
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
