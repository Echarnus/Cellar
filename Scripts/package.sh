#!/bin/sh
# Build release binaries and assemble distributable artifacts into ./dist:
#   dist/Cellar.app             the GUI app (with icon, its own copy of the CLI, and the updater)
#   dist/Cellar-App-<v>.zip     zipped app — also what the update feed points at
#   dist/cellar                 the CLI
#   dist/Cellar-CLI-<v>.zip     zipped CLI
# Used by the release workflow and for local packaging. Usage: Scripts/package.sh [version]
set -e
cd "$(dirname "$0")/.."
# Clears a Nix/devenv DEVELOPER_DIR/SDKROOT and picks a toolchain that can build the SwiftUI app.
. Scripts/select-xcode.sh
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
# The Dock shim travels with the CLI: the CLI is what spawns Wine, so it is what needs to find it.
sh Scripts/build-dock-shim.sh "$DIST/cli/share/cellar/cellar-dock-shim.dylib"
# Cellar's SDL, which Wine loads ahead of the runner's so a wheel's force feedback reaches its motor.
sh Scripts/build-sdl.sh "$DIST/cli/share/cellar/sdl"
# GPL-3.0 §4: the licence travels with the binary — and so do the notices of what is compiled into it.
mkdir -p "$DIST/cli/share/cellar/legal"
cp -R LICENSE NOTICE THIRD_PARTY_LICENSES.md licenses "$DIST/cli/share/cellar/legal/"
( cd "$DIST/cli" && zip -qr "../Cellar-CLI-$VERSION.zip" bin share )

# GUI app
APP="$DIST/Cellar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINDIR/CellarApp" "$APP/Contents/MacOS/CellarApp"
# The app's translations: one <lang>.lproj per language, which SwiftUI reads through Bundle.main.
# English is the development region, so a Mac set to a language Cellar lacks gets English.
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
# The shipped profile database. Searched after the player's own profiles, never instead of them.
mkdir -p "$APP/Contents/Resources/profiles"
cp profiles/*.toml "$APP/Contents/Resources/profiles/"
cp "$DIST/cli/share/cellar/cellar-dock-shim.dylib" "$APP/Contents/Resources/"
cp -R "$DIST/cli/share/cellar/sdl" "$APP/Contents/Resources/sdl"
cp -R "$DIST/cli/share/cellar/legal" "$APP/Contents/Resources/Legal"

[ -f Resources/AppIcon.png ] || swift Scripts/make-icon.swift Resources/AppIcon.png
ISET="$(mktemp -d)/Cellar.iconset"; mkdir -p "$ISET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s"             Resources/AppIcon.png --out "$ISET/icon_${s}x${s}.png"    >/dev/null
  sips -z "$((s*2))" "$((s*2))" Resources/AppIcon.png --out "$ISET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ISET" -o "$APP/Contents/Resources/AppIcon.icns"

# Self-update (Sparkle), only once the release signing key exists: Resources/sparkle-public-key holds
# its public half (Scripts/sparkle-keys.sh writes it), the private half is a secret of the `release`
# environment. Without it the app is built with updates switched off rather than with a feed it could never verify.
# SUAllowsAutomaticUpdates is off: an update is always shown and installed on the player's say-so,
# never swapped in on quit — Cellar may be the parent of a game that is still running.
UPDATE_KEYS=""
if [ -s Resources/sparkle-public-key ]; then
  UPDATE_KEYS="  <key>SUFeedURL</key><string>https://github.com/Echarnus/Cellar/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>$(tr -d '[:space:]' < Resources/sparkle-public-key)</string>
  <key>SUAllowsAutomaticUpdates</key><false/>"
else
  echo "warning: Resources/sparkle-public-key missing — this build will not update itself"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CellarApp</string>
  <key>CFBundleIdentifier</key><string>it.clercq.cellar.app</string>
  <key>CFBundleName</key><string>Cellar</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>nl</string></array>
  <key>CFBundleGetInfoString</key><string>Cellar — run Windows games on Apple Silicon via Wine + D3DMetal.</string>
  <key>NSHumanReadableCopyright</key><string>Free software under GPL-3.0; not affiliated with the Wine project, Valve, Blizzard, GOG, Apple or any game publisher.</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <!-- What Sparkle compares against the appcast's sparkle:version. -->
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <!-- Shown inside macOS's own permission dialog. Cellar asks for all three on first launch
       (WelcomeView) rather than letting a game trigger them mid-install; without these keys the
       dialog is the bare "would like to access files in your Documents folder" with no reason. -->
  <key>NSDocumentsFolderUsageDescription</key><string>Windows games keep their saves and settings in your Documents folder, under My Games.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Windows installers put game shortcuts on your Desktop, and some games save screenshots there.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Game installers and patches you download land in your Downloads folder.</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
$UPDATE_KEYS
</dict></plist>
PLIST
sh Scripts/bundle-app.sh "$APP" "$BINDIR"

# Seal the bundle. The linker signs the bare binary, but the Info.plist, icon and resources added
# above are not covered by it, and macOS 15+ Gatekeeper calls a quarantined bundle with an unsealed
# signature "damaged" — with no Open Anyway button. Ad-hoc unless CELLAR_SIGN_IDENTITY names a
# Developer ID; then it is also notarised and stapled when the notary key is set, so the zip the
# updater ships is trusted on its own (Scripts/sign-app.sh, Scripts/notarize.sh).
sh Scripts/sign-app.sh "$APP"
sh Scripts/notarize.sh "$APP"

( cd "$DIST" && ditto -c -k --keepParent Cellar.app "Cellar-App-$VERSION.zip" )
rm -rf "$DIST/cli"
echo "Packaged into $DIST:"; ls -1 "$DIST"
