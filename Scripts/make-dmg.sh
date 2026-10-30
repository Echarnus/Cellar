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
ditto "$APP" "$STAGE/Cellar.app"  # keeps the ad-hoc seal and xattrs intact
ln -s /Applications "$STAGE/Applications"           # drag-to-install target
cp LICENSE "$STAGE/LICENSE.txt"                     # GPL-3.0: the licence travels with the binary
cp NOTICE "$STAGE/NOTICE.txt"
cat > "$STAGE/READ ME - install.txt" <<TXT
Cellar — run Windows games on Apple Silicon.

1. Drag Cellar.app onto the Applications folder shown here.
2. First launch: right-click Cellar.app → Open (it is unsigned).
3. Cellar sets up the runtime, you sign in to Steam, then pick a game and play.

Supported games: https://echarnus.github.io/Cellar/

Cellar is free software under the GPL-3.0 (LICENSE.txt). It is built on Wine and
other people's work, credited in NOTICE.txt and in Cellar › About Cellar; their
licence texts are inside the app, in Contents/Resources/Legal.
TXT

DMG="dist/Cellar.dmg"
rm -f "$DMG"
hdiutil create -volname "Cellar $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Built $DMG"
