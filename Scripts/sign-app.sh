#!/bin/sh
# Sign a finished Cellar.app, inside-out, and verify the result. The last step that may touch the
# bundle: anything written into it afterwards breaks the seal.
# Usage: Scripts/sign-app.sh <Cellar.app>
#
# Identity: CELLAR_SIGN_IDENTITY, or ad-hoc ("-") when it is unset.
#
# - Ad-hoc is what every release has been so far. It is not trust — Gatekeeper still asks the player
#   to Open Anyway — but it makes the bundle consistent, and macOS 15+ calls a bundle whose resources
#   are not covered by its signature "damaged", with no way past it.
# - A Developer ID Application identity ("Developer ID Application: Name (TEAMID)", or its SHA-1)
#   signs with the hardened runtime and a secure timestamp, which notarisation requires. Then
#   Scripts/notarize.sh can submit the result. The hardened runtime is only switched on here:
#   ad-hoc code has no Team ID, so library validation would refuse to load Sparkle.framework.
#
# Inside-out, not `codesign --deep`: --deep signs nested code with the outer options and no
# entitlements, which Apple documents as unsuitable for distribution, and Sparkle's XPC services and
# Autoupdate helper each need their own signature for an update to install.
set -eu
APP="${1:?usage: Scripts/sign-app.sh <Cellar.app>}"
[ -d "$APP/Contents" ] || { echo "$APP is not an app bundle"; exit 1; }
IDENTITY="${CELLAR_SIGN_IDENTITY:--}"

if [ "$IDENTITY" = "-" ]; then
  echo "Signing $APP ad-hoc (no CELLAR_SIGN_IDENTITY set)."
else
  echo "Signing $APP with Developer ID identity '$IDENTITY'."
fi

sign() {
  if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$@"
  else
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$@"
  fi
}

# 1. Sparkle (present once the updater lands): its XPC services and helpers first, then the
#    framework that holds them. Paths per Sparkle's own "Code signing" documentation.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
  for xpc in "$SPARKLE"/Versions/B/XPCServices/*.xpc; do
    # Downloader.xpc carries its own sandbox entitlements; keep them.
    if [ -d "$xpc" ]; then sign --preserve-metadata=entitlements "$xpc"; fi
  done
  if [ -f "$SPARKLE/Versions/B/Autoupdate" ]; then sign "$SPARKLE/Versions/B/Autoupdate"; fi
  if [ -d "$SPARKLE/Versions/B/Updater.app" ]; then sign "$SPARKLE/Versions/B/Updater.app"; fi
  sign "$SPARKLE"
fi
# Any other framework a later change embeds.
for fw in "$APP"/Contents/Frameworks/*.framework; do
  if [ -d "$fw" ] && [ "$fw" != "$SPARKLE" ]; then sign "$fw"; fi
done

# 2. Loose code inside the bundle: the Dock shim and the CLI the app drives.
for dylib in "$APP"/Contents/Resources/*.dylib; do
  if [ -f "$dylib" ]; then sign "$dylib"; fi
done
for exe in "$APP"/Contents/MacOS/*; do
  [ "$(basename "$exe")" = "CellarApp" ] && continue
  if [ -f "$exe" ] && [ -x "$exe" ]; then sign "$exe"; fi
done

# 3. The app itself, which seals everything above into its signature.
sign "$APP"
codesign --verify --deep --strict "$APP"

if [ "$IDENTITY" != "-" ]; then
  # What Gatekeeper will say. Before notarisation this reports "Unnotarized Developer ID", which is
  # expected; it fails outright only if the signature itself is wrong.
  spctl --assess --type execute --verbose=2 "$APP" 2>&1 || true
fi
echo "Signed $APP."
