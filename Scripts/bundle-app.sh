#!/bin/sh
# Finish a Cellar.app that package.sh or install-app.sh has assembled: put the `cellar` CLI and
# Sparkle.framework inside it, then ad-hoc sign the whole bundle. Run after Info.plist is written —
# the signature seals it.
# Run from the repository root. Usage: Scripts/bundle-app.sh <Cellar.app> <swift build bin dir>
set -eu
APP="$1"
BINDIR="$2"

# The CLI the app drives, in Contents/MacOS so `Bundle.main` in the CLI is Cellar.app and it finds
# the profiles and the Dock shim in Contents/Resources. CellarRunner prefers this copy, so an
# update to the app is an update to the engine too.
[ -x "$BINDIR/cellar" ] || { echo "No cellar binary at $BINDIR/cellar — build it first"; exit 1; }
cp "$BINDIR/cellar" "$APP/Contents/MacOS/cellar"

# The updater. SwiftPM leaves the framework beside the binary it linked; inside a bundle it goes in
# Contents/Frameworks, where CellarApp's rpath looks (Package.swift). ditto keeps its symlinks and
# Sparkle's own signature intact.
[ -d "$BINDIR/Sparkle.framework" ] || { echo "No Sparkle.framework in $BINDIR — build CellarApp first"; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BINDIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

# Sparkle is MIT: its licence text travels with the copy of it we ship.
# SwiftPM clones the package into .build/checkouts; the unpacked release under .build/artifacts has
# it too.
LICENSE_FILE="$(find .build/checkouts/Sparkle .build/artifacts -maxdepth 3 -name LICENSE -path '*parkle*' \
  -type f 2>/dev/null | head -n 1)"
[ -n "$LICENSE_FILE" ] || { echo "Sparkle's LICENSE not found under .build — resolve packages first"; exit 1; }
mkdir -p "$APP/Contents/Resources/licenses"
cp "$LICENSE_FILE" "$APP/Contents/Resources/licenses/Sparkle-LICENSE.txt"

# Ad-hoc, because there is no Developer ID yet. Still load-bearing: Sparkle rejects an update whose
# bundle signature is present but broken, and a bundle that only carries the linker's signature on
# its main binary (resources unsealed, a second executable unsigned) does not verify. Inner code
# first, then the bundle; Sparkle.framework keeps the signature it shipped with.
codesign --force --sign - "$APP/Contents/MacOS/cellar"
codesign --force --sign - "$APP/Contents/Resources/cellar-dock-shim.dylib"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Bundled the cellar CLI and Sparkle into $APP, ad-hoc signed."
