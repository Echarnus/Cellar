# Skill: Shell scripts & macOS packaging

Best practices for `Scripts/*.sh` and how Cellar assembles its `.app`, DMG, and release artifacts.
Read [`../AGENTS.md`](../AGENTS.md) first.

## Shell style

- **POSIX `sh`**, `set -e` at the top, `cd "$(dirname "$0")/.."` so a script runs from anywhere.
- Quote every expansion (`"$VAR"`). Absolute or `$0`-relative paths, never assume the CWD.
- Fail loudly with a clear message when a precondition is missing (e.g. `dist/Cellar.app` absent).
- Keep scripts idempotent — safe to re-run.

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

## Packaging traps (already solved — don't reintroduce)

- **Case-insensitive filesystem collision.** The zips are named `Cellar-App-<v>.zip` and
  `Cellar-CLI-<v>.zip` deliberately — a naive `Cellar-<v>.zip` / `cellar-<v>.zip` pair collides on
  macOS's case-insensitive FS and one silently overwrites the other.
- **Versionless DMG.** `make-dmg.sh` emits `dist/Cellar.dmg` (no version in the name) so the site's
  `releases/latest/download/Cellar.dmg` link always resolves. Don't add a version back.
- **Unsigned artifacts.** Releases are unsigned/unnotarised; release notes tell users to right-click →
  Open or clear the quarantine flag. If you add signing, update the notes.

## Never package

Game files, bottles, runners, downloaded depots, Apple's D3DMetal, or logs — see the hard rules in
[`../AGENTS.md`](../AGENTS.md). `.gitignore` enforces most of this; keep it that way.

## Verify

The changed script runs clean from a fresh checkout; the resulting `.app` launches; `Info.plist`
carries the expected keys (`/usr/libexec/PlistBuddy -c "Print" …`); release naming matches what
`release.yml` and the site expect.

Related: [`swift.md`](swift.md) · [`web.md`](web.md) · [`../docs/RELEASING.md`](../docs/RELEASING.md)
