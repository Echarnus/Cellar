#!/bin/sh
# Build release binaries and assemble distributable artifacts into ./dist:
#   dist/Cellar.app        the GUI app (with icon)
#   dist/Cellar-<v>.zip    zipped app
#   dist/cellar            the CLI
#   dist/cellar-<v>.zip    zipped CLI
# Used by the release workflow and for local packaging. Usage: Scripts/package.sh [version]
set -e
cd "$(dirname "$0")/.."
unset DEVELOPER_DIR SDKROOT
VERSION="${1:-0.0.0-dev}"
DIST="dist"; rm -rf "$DIST"; mkdir -p "$DIST"

echo "Building release (cellar + CellarApp)…"
swift build -c release
BINDIR="$(swift build -c release --show-bin-path)"

# CLI. The zip carries the profile database next to the binary in the layout Cellar looks for
# (<prefix>/bin/cellar + <prefix>/share/cellar/profiles), so an installed CLI knows the games.
cp "$BINDIR/cellar" "$DIST/cellar"
mkdir -p "$DIST/cli/bin" "$DIST/cli/share/cellar/profiles"
cp "$BINDIR/cellar" "$DIST/cli/bin/cellar"
cp profiles/*.toml "$DIST/cli/share/cellar/profiles/"
( cd "$DIST/cli" && zip -qr "../Cellar-CLI-$VERSION.zip" bin share )

# GUI app
APP="$DIST/Cellar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINDIR/CellarApp" "$APP/Contents/MacOS/CellarApp"
# The shipped profile database. Searched after the player's own profiles, never instead of them.
mkdir -p "$APP/Contents/Resources/profiles"
cp profiles/*.toml "$APP/Contents/Resources/profiles/"

[ -f Resources/AppIcon.png ] || swift Scripts/make-icon.swift Resources/AppIcon.png
ISET="$(mktemp -d)/Cellar.iconset"; mkdir -p "$ISET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s"             Resources/AppIcon.png --out "$ISET/icon_${s}x${s}.png"    >/dev/null
  sips -z "$((s*2))" "$((s*2))" Resources/AppIcon.png --out "$ISET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ISET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CellarApp</string>
  <key>CFBundleIdentifier</key><string>it.clercq.cellar.app</string>
  <key>CFBundleName</key><string>Cellar</string>
  <key>CFBundleGetInfoString</key><string>Cellar — run Windows games on Apple Silicon via Wine + D3DMetal.</string>
  <key>NSHumanReadableCopyright</key><string>Free software under GPL-3.0. Not affiliated with Valve or Apple.</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <!-- Shown inside macOS's own permission dialog. Cellar asks for all three on first launch
       (WelcomeView) rather than letting a game trigger them mid-install; without these keys the
       dialog is the bare "would like to access files in your Documents folder" with no reason. -->
  <key>NSDocumentsFolderUsageDescription</key><string>Windows games keep their saves and settings in your Documents folder, under My Games.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Windows installers put game shortcuts on your Desktop, and some games save screenshots there.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Game installers and patches you download land in your Downloads folder.</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST

( cd "$DIST" && ditto -c -k --keepParent Cellar.app "Cellar-App-$VERSION.zip" )
rm -rf "$DIST/cli"
echo "Packaged into $DIST:"; ls -1 "$DIST"
