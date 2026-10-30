#!/bin/sh
# Sign a release's app zip and write its Sparkle update feed, dist/appcast.xml. Run after
# Scripts/package.sh, which builds the zip and resolves Sparkle (whose sign_update this uses).
# The release workflow uploads the feed as a release asset; installed copies of Cellar read it at
# https://github.com/Echarnus/Cellar/releases/latest/download/appcast.xml.
#
# The EdDSA private key comes from the environment (SPARKLE_ED_PRIVATE_KEY, a repository secret)
# and is handed to sign_update on stdin — never on a command line, never written to disk.
# Usage: SPARKLE_ED_PRIVATE_KEY=… Scripts/make-appcast.sh <version> <release-notes.md>
set -eu
cd "$(dirname "$0")/.."
[ $# -eq 2 ] || { echo "usage: Scripts/make-appcast.sh <version> <release-notes.md>"; exit 2; }
VERSION="$1"
NOTES="$2"
ZIP="dist/Cellar-App-$VERSION.zip"

[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ] || { echo "SPARKLE_ED_PRIVATE_KEY is not set — no feed written"; exit 1; }
[ -s Resources/sparkle-public-key ] || { echo "Resources/sparkle-public-key missing — run Scripts/sparkle-keys.sh"; exit 1; }
[ -f "$ZIP" ] || { echo "$ZIP missing — run Scripts/package.sh $VERSION first"; exit 1; }
[ -f "$NOTES" ] || { echo "Release notes $NOTES missing"; exit 1; }

# SwiftPM unpacks Sparkle's release, tools included, under .build/artifacts.
SIGN="$(find .build/artifacts -path '*/bin/sign_update' -type f 2>/dev/null | head -n 1)"
[ -n "$SIGN" ] || { echo "sign_update not found under .build/artifacts — build CellarApp first"; exit 1; }

SIGNATURE="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$SIGN" -p --ed-key-file - "$ZIP")"
LENGTH="$(wc -c < "$ZIP" | tr -d ' ')"
# Check the signature verifies; make-appcast.py then checks this key is the one the app carries.
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$SIGN" --verify --ed-key-file - "$ZIP" "$SIGNATURE" >/dev/null

python3 Scripts/make-appcast.py \
  --version "$VERSION" \
  --notes "$NOTES" \
  --signature "$SIGNATURE" \
  --public-key "$(tr -d '[:space:]' < Resources/sparkle-public-key)" \
  --length "$LENGTH" \
  --out dist/appcast.xml
echo "Wrote dist/appcast.xml for Cellar $VERSION ($LENGTH bytes, signed)."
