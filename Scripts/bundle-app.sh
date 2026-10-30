#!/bin/sh
# Put the `cellar` CLI and Sparkle.framework inside a Cellar.app that package.sh or install-app.sh
# has assembled. Run before the bundle's ad-hoc seal (`codesign --deep` in both scripts), which then
# covers both — Sparkle refuses an update whose bundle signature is present but broken.
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
# Contents/Frameworks, where CellarApp's rpath looks (Package.swift). ditto keeps the framework's
# symlinks, which codesign needs to seal it.
[ -d "$BINDIR/Sparkle.framework" ] || { echo "No Sparkle.framework in $BINDIR — build CellarApp first"; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BINDIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

echo "Bundled the cellar CLI and Sparkle into $APP."
