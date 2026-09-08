#!/bin/sh
# Build CellarApp and install it as ~/Applications/Cellar.app (the native "Steam-like" front-end).
# Requires the `cellar` CLI on PATH or ~/.local/bin for actions.
set -e
cd "$(dirname "$0")/.."
# A Nix/devenv shell may export DEVELOPER_DIR/SDKROOT pointing at a non-macOS SDK; use Xcode's.
unset DEVELOPER_DIR SDKROOT
echo "Building CellarApp (release)…"
swift build -c release --product CellarApp
BIN=".build/release/CellarApp"
[ -x "$BIN" ] || { echo "Build produced no CellarApp binary at $BIN"; exit 1; }

# One version, from CellarKit. A diagnostics report that names a version nobody shipped is worse
# than no version at all, and a dev install used to claim 0.1 forever.
VERSION="$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/CellarKit/Version.swift)"
VERSION="${VERSION:-0.0.0}-dev"

APP="$HOME/Applications/Cellar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CellarApp"

# App icon: build a multi-resolution .icns from Resources/AppIcon.png (regenerate it if missing).
ICON_SRC="Resources/AppIcon.png"
[ -f "$ICON_SRC" ] || swift Scripts/make-icon.swift "$ICON_SRC"
if [ -f "$ICON_SRC" ]; then
  ISET="$(mktemp -d)/Cellar.iconset"; mkdir -p "$ISET"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s"       "$ICON_SRC" --out "$ISET/icon_${s}x${s}.png"    >/dev/null
    sips -z "$((s*2))" "$((s*2))" "$ICON_SRC" --out "$ISET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ISET" -o "$APP/Contents/Resources/AppIcon.icns"
  ICON_KEY='  <key>CFBundleIconFile</key><string>AppIcon</string>'
fi
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
$ICON_KEY
</dict></plist>
PLIST
# Ship the profile database inside the bundle. Cellar searches this *after* the player's own
# ~/Library/Application Support/Cellar/profiles, so shipping a new game (or a fixed profile) never
# overwrites a profile someone has edited by hand.
mkdir -p "$APP/Contents/Resources/profiles"
cp profiles/*.toml "$APP/Contents/Resources/profiles/"
echo "Bundled $(ls profiles/*.toml | wc -l | tr -d ' ') game profiles."

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
echo "Installed $APP  —  open it with:  open \"$APP\""
