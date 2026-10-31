#!/bin/sh
# Build the drag-to-Applications installer, dist/Cellar.dmg, from dist/Cellar.app. Run after
# Scripts/package.sh. Usage: Scripts/make-dmg.sh [version]
#
# What the player sees when the image opens: a fixed 660×420 window with a background drawn for it
# (make-dmg-background.swift), Cellar on the left, an arrow, the Applications folder on the right,
# and the licence and read-me in one folder underneath — the window every Mac installer DMG has, so
# there is nothing to work out. Cellar's icon is the volume icon too.
#
# The window's look is stored in the volume's .DS_Store, and the only supported way to write that
# is to have Finder lay the window out (AppleScript). That needs a logged-in Finder, which GitHub's
# macOS runners have. If Finder will not do it, the DMG is still built and still installs — just
# without the styled window — and the script says so loudly rather than failing a release over
# looks. Set CELLAR_DMG_STRICT=1 to make that a failure instead.
#
# Signing: with CELLAR_SIGN_IDENTITY set to a Developer ID Application identity, the image is
# signed too, and Scripts/notarize.sh submits and staples it when the notary credentials are set
# (see docs/RELEASING.md). Without them the DMG is unsigned, as it has always been.
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:-0.0.0-dev}"
APP="dist/Cellar.app"
DMG="dist/Cellar.dmg"   # versionless on purpose: releases/latest/download/Cellar.dmg must resolve
VOLNAME="Cellar"        # the window title; the version is in the app, not in a title bar
[ -d "$APP" ] || { echo "dist/Cellar.app missing — run Scripts/package.sh first"; exit 1; }

TMP="$(mktemp -d)"
MOUNT=""
cleanup() {
  [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

# --- Contents ---------------------------------------------------------------------------------
STAGE="$TMP/stage"
INFO="$STAGE/Licence and Read Me"
mkdir -p "$STAGE/.background" "$INFO"
ditto "$APP" "$STAGE/Cellar.app"                    # keeps the bundle's signature and xattrs intact
ln -s /Applications "$STAGE/Applications"           # the drag-to-install target
cp ../LICENSE "$INFO/LICENSE.txt"                      # GPL-3.0: the licence travels with the binary
cp ../NOTICE "$INFO/NOTICE.txt"
# A notarised build opens with a double-click; only an ad-hoc one needs the Open Anyway step, and
# the read-me must not describe a hurdle the player will never meet (docs/RELEASING.md).
if [ "${CELLAR_SIGN_IDENTITY:--}" != "-" ] && [ -n "${NOTARY_KEY_ID:-}" ]; then
  FIRST_OPEN="2. Open Cellar from your Applications folder."
else
  FIRST_OPEN="2. Open Cellar from your Applications folder.
   If macOS says it cannot check Cellar for malicious software, open System Settings ›
   Privacy & Security, scroll down to Cellar and click Open Anyway. You only do this once."
fi
cat > "$INFO/Read Me.txt" <<TXT
Cellar $VERSION — run Windows games on Apple Silicon.

Installing
1. Drag Cellar onto the Applications folder in this window.
$FIRST_OPEN
3. On its first start Cellar downloads what every game needs — the Wine runner and the
   Windows Steam client, a few gigabytes — in the background while you sign in, so your
   first game does not start with a long wait.

Uninstalling
Cellar › Uninstall Cellar… removes the app and everything it downloaded, and offers to keep
your save games (copied to Documents › Cellar Saved Games first). If you also use the
cellar command in Terminal, cellar uninstall-cellar does the same.

Supported games: https://echarnus.github.io/Cellar/

Cellar is free software under the GPL-3.0 (LICENSE.txt). It is built on Wine and other
people's work, credited in NOTICE.txt and in Cellar › About Cellar; their licence texts are
inside the app, in Contents/Resources/Legal. Nothing proprietary is in this disk image:
Apple's D3DMetal and the Steam client are downloaded on your Mac, from their publishers.
TXT

# The background: drawn at 1× and 2× and joined into one TIFF, so Retina screens get the sharp one.
swift Scripts/make-dmg-background.swift "$TMP" >/dev/null
tiffutil -cathidpicheck "$TMP/background.png" "$TMP/background@2x.png" \
  -out "$STAGE/.background/background.tiff" >/dev/null 2>&1

# The volume icon is the app's own.
cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

# --- A writable image Finder can lay out -------------------------------------------------------
# HFS+, not APFS: it is what Finder's background and icon-position storage has always been tested
# on, and it mounts on every macOS Cellar supports. Sized with headroom for Finder's .DS_Store.
RW="$TMP/rw.dmg"
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 32 ))
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -size "${SIZE_MB}m" \
  -ov "$RW" >/dev/null
# Not -nobrowse: Finder has to see the volume to lay its window out.
MOUNT="$(hdiutil attach "$RW" -readwrite -noverify -noautoopen \
  | awk -F '\t' '/\/Volumes\// { print $NF; exit }')"
[ -n "$MOUNT" ] || { echo "Could not mount $RW"; exit 1; }
# hdiutil may have picked "Cellar 1" if a "Cellar" volume is already mounted; Finder needs the name.
DISK="$(basename "$MOUNT")"

# Tell Finder the volume has a custom icon. SetFile ships with the Command Line Tools.
if command -v SetFile >/dev/null 2>&1; then
  SetFile -c icnC "$MOUNT/.VolumeIcon.icns"
  SetFile -a C "$MOUNT"
else
  echo "warning: SetFile not found — the disk image will show a generic volume icon"
fi

# Positions are icon centres, in points from the window's top-left. They match the drawing in
# make-dmg-background.swift; change one, change both.
styled=1
if ! osascript >/dev/null <<APPLESCRIPT
tell application "Finder"
  tell disk "$DISK"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    -- {left, top, right, bottom} on screen; the content area is 660 × 420.
    set the bounds of container window to {200, 120, 860, 568}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 100
    set text size of viewOptions to 13
    set label position of viewOptions to bottom
    set shows item info of viewOptions to false
    set shows icon preview of viewOptions to false
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "Cellar.app" of container window to {170, 185}
    set position of item "Applications" of container window to {490, 185}
    set position of item "Licence and Read Me" of container window to {330, 330}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
then
  styled=0
fi

# Finder writes .DS_Store lazily; wait until it is there before the image is sealed.
i=0
while [ "$styled" -eq 1 ] && [ ! -f "$MOUNT/.DS_Store" ] && [ "$i" -lt 10 ]; do
  sleep 1; i=$((i + 1))
done
[ -f "$MOUNT/.DS_Store" ] || styled=0

if [ "$styled" -eq 0 ]; then
  msg="Finder did not lay out the installer window, so Cellar.dmg has the default Finder look. It still installs."
  if [ "${CELLAR_DMG_STRICT:-0}" = "1" ]; then echo "error: $msg"; exit 1; fi
  # A GitHub Actions annotation when run there, a plain warning anywhere else.
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::warning::$msg"; else echo "warning: $msg"; fi
fi

# The helpers stay in the image (Finder reads the background from it) but out of sight.
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a V "$MOUNT/.background" 2>/dev/null || true
  SetFile -a V "$MOUNT/.VolumeIcon.icns" 2>/dev/null || true
fi
rm -rf "$MOUNT/.fseventsd" "$MOUNT/.Trashes" 2>/dev/null || true
chmod -Rf go-w "$MOUNT" 2>/dev/null || true
sync
hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -quiet -force
MOUNT=""

# --- The read-only, compressed image players download ------------------------------------------
# ULMO (LZMA) is the smallest format macOS mounts natively, from 10.15 — Cellar needs 13.
rm -f "$DMG"
hdiutil convert "$RW" -format ULMO -o "$DMG" >/dev/null

# Signed and notarised only when there is a Developer ID to do it with (Scripts/sign-app.sh).
IDENTITY="${CELLAR_SIGN_IDENTITY:--}"
if [ "$IDENTITY" != "-" ]; then
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"
  codesign --verify --strict "$DMG"
  sh Scripts/notarize.sh "$DMG"
fi
hdiutil verify "$DMG" >/dev/null
echo "Built $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
