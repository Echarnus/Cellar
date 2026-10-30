#!/bin/sh
# Notarise a signed Cellar.app or Cellar.dmg with Apple and staple the ticket to it, so Gatekeeper
# opens it without the player having to go through Privacy & Security › Open Anyway.
# Usage: Scripts/notarize.sh <Cellar.app | Cellar.dmg>
#
# Needs a paid Apple Developer account. Until its credentials are supplied this does nothing and
# says so, which is what every release does today. Credentials come from the environment, as an
# App Store Connect API key (the form Apple recommends for CI; no Apple ID password involved):
#
#   NOTARY_KEY_ID      the key's ID, e.g. 2X9R4HXF34
#   NOTARY_ISSUER_ID   the issuer UUID shown above the key list in App Store Connect
#   NOTARY_KEY         the contents of the AuthKey_<id>.p8 file
#
# The key is written to a private temporary file for notarytool and removed straight after. The
# item must already be signed with a Developer ID and the hardened runtime (Scripts/sign-app.sh).
set -eu
ITEM="${1:?usage: Scripts/notarize.sh <Cellar.app | Cellar.dmg>}"
[ -e "$ITEM" ] || { echo "$ITEM does not exist"; exit 1; }

if [ -z "${NOTARY_KEY_ID:-}" ] || [ -z "${NOTARY_ISSUER_ID:-}" ] || [ -z "${NOTARY_KEY:-}" ]; then
  echo "Not notarising $ITEM: NOTARY_KEY_ID, NOTARY_ISSUER_ID and NOTARY_KEY are not all set."
  exit 0
fi
if [ "${CELLAR_SIGN_IDENTITY:--}" = "-" ]; then
  echo "error: notarisation needs a Developer ID signature, and CELLAR_SIGN_IDENTITY is not set."
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
chmod 700 "$TMP"
KEY="$TMP/AuthKey.p8"
printf '%s\n' "$NOTARY_KEY" > "$KEY"
chmod 600 "$KEY"

# notarytool takes a zip, a dmg or a pkg — not a bare .app.
case "$ITEM" in
  *.app) SUBMIT="$TMP/$(basename "$ITEM" .app).zip"
         ditto -c -k --keepParent "$ITEM" "$SUBMIT" ;;
  *)     SUBMIT="$ITEM" ;;
esac

echo "Submitting $(basename "$ITEM") to Apple's notary service (this usually takes a few minutes)…"
OUT="$TMP/result.plist"
if ! xcrun notarytool submit "$SUBMIT" --key "$KEY" --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER_ID" --wait --timeout 30m --output-format plist > "$OUT"; then
  echo "error: notarytool could not complete the submission."
  cat "$OUT" 2>/dev/null || true
  exit 1
fi
STATUS="$(/usr/libexec/PlistBuddy -c 'Print :status' "$OUT" 2>/dev/null || echo unknown)"
ID="$(/usr/libexec/PlistBuddy -c 'Print :id' "$OUT" 2>/dev/null || echo unknown)"
if [ "$STATUS" != "Accepted" ]; then
  echo "error: Apple did not accept $(basename "$ITEM") (status: $STATUS). Apple's log says why:"
  xcrun notarytool log "$ID" --key "$KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" || true
  exit 1
fi

# Staple, so the ticket travels with the file and Gatekeeper need not reach Apple to check it.
xcrun stapler staple "$ITEM"
xcrun stapler validate "$ITEM"
echo "Notarised and stapled $(basename "$ITEM") (submission $ID)."
