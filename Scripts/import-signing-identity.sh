#!/bin/sh
# CI only: put the Developer ID certificate into a throwaway keychain so codesign can use it, and
# print the identity to sign with. A release job runs this before Scripts/package.sh.
# Usage: eval "$(Scripts/import-signing-identity.sh)"   → exports CELLAR_SIGN_IDENTITY
#
#   DEVELOPER_ID_P12           the "Developer ID Application" certificate and its private key,
#                              exported from Keychain Access as .p12, then base64-encoded
#   DEVELOPER_ID_P12_PASSWORD  the password chosen at export
#
# Without them it prints nothing and the build stays ad-hoc signed. The keychain lives in the
# runner's temporary directory and is gone with the runner; its password is random and never shown.
set -eu
if [ -z "${DEVELOPER_ID_P12:-}" ] || [ -z "${DEVELOPER_ID_P12_PASSWORD:-}" ]; then
  echo "echo 'No Developer ID certificate supplied — the build stays ad-hoc signed.'"
  exit 0
fi

DIR="${RUNNER_TEMP:-$(mktemp -d)}"
KEYCHAIN="$DIR/cellar-signing.keychain-db"
P12="$DIR/cellar-signing.p12"
PASS="$(openssl rand -base64 24)"
trap 'rm -f "$P12"' EXIT

printf '%s' "$DEVELOPER_ID_P12" | base64 --decode > "$P12"
security create-keychain -p "$PASS" "$KEYCHAIN" >&2
security set-keychain-settings -lut 21600 "$KEYCHAIN" >&2
security unlock-keychain -p "$PASS" "$KEYCHAIN" >&2
security import "$P12" -k "$KEYCHAIN" -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign >&2
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASS" "$KEYCHAIN" >/dev/null
# Searched alongside the login keychain, so codesign finds the identity.
# shellcheck disable=SC2046 # the existing list is several quoted paths, split on purpose
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" \
  | awk '/Developer ID Application/ { print $2; exit }')"
[ -n "$IDENTITY" ] || { echo "No Developer ID Application identity in the supplied certificate" >&2; exit 1; }
echo "export CELLAR_SIGN_IDENTITY='$IDENTITY'"
