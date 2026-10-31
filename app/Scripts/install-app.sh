#!/bin/sh
# Build CellarApp and install it as ~/Applications/Cellar.app (the native "Steam-like" front-end).
# Also installs the matching `cellar` CLI into ~/.local/bin, which the app drives for every action.
set -e
cd "$(dirname "$0")/.."
# Clears a Nix/devenv DEVELOPER_DIR/SDKROOT and picks a toolchain that can build the SwiftUI app.
. Scripts/select-xcode.sh

# Build everything — both products, the Dock shim and the icon — before touching anything installed:
# a failure leaves the previous app and CLI in place as a matching pair, never a new app driving an
# old CLI.
echo "Building CellarApp and the cellar CLI (release)…"
swift build -c release --product CellarApp
swift build -c release --product cellar
BIN=".build/release/CellarApp"
[ -x "$BIN" ] || { echo "Build produced no CellarApp binary at $BIN"; exit 1; }
[ -x ".build/release/cellar" ] || { echo "Build produced no cellar binary at .build/release/cellar"; exit 1; }
# The Dock shim, which keeps a bottle's Steam/Battle.net out of the Dock while a game starts.
SHIM=".build/cellar-dock-shim.dylib"
sh Scripts/build-dock-shim.sh "$SHIM"
# Cellar's SDL, loaded by Wine ahead of the runner's so wheel force feedback reaches the motor.
SDL=".build/sdl"
sh Scripts/build-sdl.sh "$SDL"

# App icon: build a multi-resolution .icns from Resources/AppIcon.png (regenerate it if missing).
ICON_SRC="Resources/AppIcon.png"
ICNS=""
[ -f "$ICON_SRC" ] || swift Scripts/make-icon.swift "$ICON_SRC"
if [ -f "$ICON_SRC" ]; then
  ISET="$(mktemp -d)/Cellar.iconset"; mkdir -p "$ISET"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s"       "$ICON_SRC" --out "$ISET/icon_${s}x${s}.png"    >/dev/null
    sips -z "$((s*2))" "$((s*2))" "$ICON_SRC" --out "$ISET/icon_${s}x${s}@2x.png" >/dev/null
  done
  ICNS=".build/AppIcon.icns"
  iconutil -c icns "$ISET" -o "$ICNS"
fi

# Copy then rename, for files outside the app bundle: a `cellar launch` — and the Steam or Battle.net
# client it injected the shim into — may be running for a whole play session, and rewriting a signed
# binary in place can get it killed.
install_file() {
  cp "$1" "$2.new"
  mv -f "$2.new" "$2"
}

# One version, from CellarKit. A diagnostics report that names a version nobody shipped is worse
# than no version at all, and a dev install used to claim 0.1 forever.
VERSION="$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/CellarKit/Core/CellarVersion.swift)"
VERSION="${VERSION:-0.0.0}-dev"

APP="$HOME/Applications/Cellar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CellarApp"
if [ -n "$ICNS" ]; then
  cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
  ICON_KEY='  <key>CFBundleIconFile</key><string>AppIcon</string>'
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
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <!-- Shown inside macOS's own permission dialog. Cellar asks for all three on first launch
       (WelcomeView) rather than letting a game trigger them mid-install; without these keys the
       dialog is the bare "would like to access files in your Documents folder" with no reason. -->
  <key>NSDocumentsFolderUsageDescription</key><string>Windows games keep their saves and settings in your Documents folder, under My Games.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Windows installers put game shortcuts on your Desktop, and some games save screenshots there.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Game installers and patches you download land in your Downloads folder.</string>
$ICON_KEY
</dict></plist>
PLIST
# The app's translations: one <lang>.lproj per language, which SwiftUI reads through Bundle.main.
# English is the development region, so a Mac set to a language Cellar lacks gets English.
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
# Ship the profile database inside the bundle. Cellar searches this *after* the player's own
# ~/Library/Application Support/Cellar/profiles, so shipping a new game (or a fixed profile) never
# overwrites a profile someone has edited by hand.
mkdir -p "$APP/Contents/Resources/profiles"
cp ../profiles/*.toml "$APP/Contents/Resources/profiles/"
echo "Bundled $(ls ../profiles/*.toml | wc -l | tr -d ' ') game profiles."

# The Dock shim goes in the bundle, and beside the CLI's own state, because it is the `cellar`
# binary — not the app — that spawns Wine, and the CLI may live anywhere on PATH.
cp "$SHIM" "$APP/Contents/Resources/cellar-dock-shim.dylib"
rm -rf "$APP/Contents/Resources/sdl"
cp -R "$SDL" "$APP/Contents/Resources/sdl"
# The same Legal/ folder package.sh ships, so a local install matches a release.
rm -rf "$APP/Contents/Resources/Legal"
mkdir -p "$APP/Contents/Resources/Legal"
cp -R ../LICENSE ../NOTICE ../THIRD_PARTY_LICENSES.md ../licenses "$APP/Contents/Resources/Legal/"
mkdir -p "$HOME/Library/Application Support/Cellar"
install_file "$SHIM" "$HOME/Library/Application Support/Cellar/cellar-dock-shim.dylib"

# The app does every action through the `cellar` CLI (~/.local/bin is where it looks when PATH has
# none), so installing the app alone leaves it driving whatever older CLI is there. Same layout as
# package.sh's CLI zip: <prefix>/bin/cellar beside <prefix>/share/cellar/{profiles,dock shim}, which
# is where the CLI looks for both — an old share/ is an old game list, not just an old binary.
PREFIX="$HOME/.local"
mkdir -p "$PREFIX/bin" "$PREFIX/share/cellar/profiles"
install_file .build/release/cellar "$PREFIX/bin/cellar"
rm -f "$PREFIX/share/cellar/profiles/"*.toml
cp ../profiles/*.toml "$PREFIX/share/cellar/profiles/"
install_file "$SHIM" "$PREFIX/share/cellar/cellar-dock-shim.dylib"
rm -rf "$PREFIX/share/cellar/sdl"
cp -R "$SDL" "$PREFIX/share/cellar/sdl"
echo "Installed the cellar CLI at $PREFIX/bin/cellar (profiles in $PREFIX/share/cellar)."

# The bundled CLI and the updater framework. No SUFeedURL/SUPublicEDKey above, on purpose: a build
# from source must never replace itself with a release, so its updater stays off and Settings says so.
sh Scripts/bundle-app.sh "$APP" .build/release

# Same ad-hoc seal as package.sh: the Info.plist and resources were added after the linker signed
# the binary, and an unsealed bundle is one macOS may refuse to open.
codesign --force --deep --sign - "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
echo "Installed $APP  —  open it with:  open \"$APP\""
