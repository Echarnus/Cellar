#!/bin/sh
# One-time setup for Cellar's self-updater, run by the maintainer on their Mac.
#
# Makes (or reuses) the EdDSA key pair that signs every update, keeps the private key in the login
# keychain, stores a copy as the secret SPARKLE_ED_PRIVATE_KEY of the `release` environment (only the
# tag-triggered publish job can read it, never a pull-request run),
# and writes the public key to Resources/sparkle-public-key for package.sh to put in Info.plist.
# Commit that file; from the next release on, Cellar updates itself.
#
# Running it again is safe: an existing key is reused, never replaced. Replacing it would strand
# every installed copy — they only accept updates signed by the key they shipped with.
# Usage: Scripts/sparkle-keys.sh
set -eu
cd "$(dirname "$0")/.."
. Scripts/select-xcode.sh
ACCOUNT="cellar"
REPO="Echarnus/Cellar"

swift package resolve >/dev/null
GEN="$(find .build/artifacts -path '*/bin/generate_keys' -type f | head -n 1)"
[ -n "$GEN" ] || { echo "generate_keys not found under .build/artifacts"; exit 1; }

# Creates the key the first time, prints the existing one after that. macOS may ask to let
# generate_keys use the keychain — allow it.
"$GEN" --account "$ACCOUNT" >/dev/null
"$GEN" --account "$ACCOUNT" -p > Resources/sparkle-public-key
echo "Public key written to Resources/sparkle-public-key: $(cat Resources/sparkle-public-key)"

if command -v gh >/dev/null 2>&1; then
  # Exported into a private temporary directory and removed straight after, whatever happens.
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  chmod 700 "$TMP"
  "$GEN" --account "$ACCOUNT" -x "$TMP/key"
  # Creating the environment is idempotent; the secret cannot be set before it exists.
  gh api --silent -X PUT "repos/$REPO/environments/release"
  gh secret set SPARKLE_ED_PRIVATE_KEY --repo "$REPO" --env release < "$TMP/key"
  echo "Stored the private key as SPARKLE_ED_PRIVATE_KEY in the release environment of $REPO."
else
  echo "The GitHub CLI (gh) is not installed, so the secret was not set. Either install it"
  echo "(brew install gh, gh auth login) and run this again, or export the key with"
  echo "  $GEN --account $ACCOUNT -x ~/Desktop/cellar-sparkle.key"
  echo "paste the file's contents into GitHub › Settings › Environments › release › Add secret as"
  echo "SPARKLE_ED_PRIVATE_KEY, then delete the file."
fi
echo "Next: commit Resources/sparkle-public-key on a branch and open a pull request for it."
