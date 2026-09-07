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

APP="$HOME/Applications/Cellar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CellarApp"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CellarApp</string>
  <key>CFBundleIdentifier</key><string>it.clercq.cellar.app</string>
  <key>CFBundleName</key><string>Cellar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
echo "Installed $APP  —  open it with:  open \"$APP\""
