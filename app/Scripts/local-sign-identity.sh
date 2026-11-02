#!/bin/sh
# Sourced by install-app.sh: pick the identity a build from source is signed with on this Mac, so the
# keychain keeps trusting `cellar` across rebuilds.
#
# Why: the CLI keeps the Steam and GOG sign-ins in the login keychain, and an item there trusts the
# exact code that was allowed to read it. An ad-hoc signature is a hash of the binary, so every
# rebuild is a stranger and macOS asks for the login password again ("cellar wants to use your
# confidential information stored in 'Cellar — Steam sign-in'"), however often "Always Allow" was
# pressed. A certificate Apple issued carries a Team ID, and the keychain trusts that Team ID and
# the binary's identifier instead of its hash — so "Always Allow" sticks from then on.
#
# Order:
#   1. CELLAR_LOCAL_SIGN_IDENTITY, if set ("-" forces ad-hoc).
#   2. The first valid "Apple Development" identity in the keychains — free with any Apple ID, made
#      once in Xcode › Settings › Accounts › Manage Certificates › + › Apple Development.
#   3. Ad-hoc ("-"), as before, with a note saying how to stop the prompts.
#
# Sets LOCAL_SIGN_IDENTITY. Never a Developer ID: that one is for releases (sign-app.sh) and turns on
# the hardened runtime, which a local install does not use.
LOCAL_SIGN_IDENTITY="${CELLAR_LOCAL_SIGN_IDENTITY:-}"
if [ -z "$LOCAL_SIGN_IDENTITY" ]; then
  # The SHA-1, not the name: two certificates can share a name after a renewal, and codesign refuses
  # an ambiguous name.
  LOCAL_SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^ *[0-9][0-9]*) \([0-9A-F]\{40\}\) "Apple Development: .*/\1/p' | head -n 1)"
fi
if [ -z "$LOCAL_SIGN_IDENTITY" ] || [ "$LOCAL_SIGN_IDENTITY" = "-" ]; then
  LOCAL_SIGN_IDENTITY="-"
  echo "Signing ad-hoc: macOS will ask once more for keychain access to your sign-ins after this install."
  echo "  To stop that for good on this Mac: Xcode › Settings › Accounts › Manage Certificates › + › Apple Development."
else
  echo "Signing with your local identity $LOCAL_SIGN_IDENTITY, so the keychain keeps trusting cellar across rebuilds."
fi

# The identifier the keychain trusts together with the Team ID. One for the CLI wherever it lives —
# ~/.local/bin and inside the app — so allowing one allows both.
# shellcheck disable=SC2034  # read by install-app.sh, which sources this file
CELLAR_CLI_IDENTIFIER="it.clercq.cellar.cli"

# local_sign <path> [identifier]: no hardened runtime and no timestamp (a local build, not a release).
local_sign() {
  if [ -n "${2:-}" ]; then
    codesign --force --sign "$LOCAL_SIGN_IDENTITY" --identifier "$2" "$1"
  else
    codesign --force --sign "$LOCAL_SIGN_IDENTITY" "$1"
  fi
}
