#!/bin/sh
# Build a drag-to-Applications installer DMG from dist/Cellar.app. Run after Scripts/package.sh.
# Usage: Scripts/make-dmg.sh [version]
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-0.0.0-dev}"
APP="dist/Cellar.app"
[ -d "$APP" ] || { echo "dist/Cellar.app missing — run Scripts/package.sh first"; exit 1; }

STAGE="$(mktemp -d)/Cellar"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Cellar.app"
ln -s /Applications "$STAGE/Applications"           # drag-to-install target
cat > "$STAGE/READ ME - install.txt" <<TXT
Cellar — run Windows games on Apple Silicon.

1. Drag Cellar.app onto the Applications folder shown here.
2. First launch: right-click Cellar.app → Open (it is unsigned).
3. Cellar sets up the runtime, you sign in to Steam, then pick a game and play.

Supported games: https://echarnus.github.io/Cellar/
TXT

DMG="dist/Cellar.dmg"
rm -f "$DMG"
hdiutil create -volname "Cellar $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Built $DMG"
