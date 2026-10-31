#!/bin/sh
# One command, once, on the maintainer's Mac: make the two keys releases sign with, keep the private
# halves out of the repository, and put the public halves where the build reads them.
#
#   1. The update key (Sparkle EdDSA): Scripts/sparkle-keys.sh — login keychain + the
#      SPARKLE_ED_PRIVATE_KEY secret of the `release` environment + Resources/sparkle-public-key.
#   2. The game-database key (Ed25519): kept in the login keychain (service
#      it.clercq.cellar.release.profiles) as the backup, stored as the PROFILES_SIGNING_KEY secret of
#      the `release` environment, and its public half written into ProfileUpdates.publicKey.
#
# Why a person has to run it: the app can only ever carry public keys (a copy that could sign would
# let anyone sign a fake update), and a workflow's GITHUB_TOKEN cannot write secrets. So the one
# place a private key is made is the maintainer's own Mac, signed in to GitHub with `gh`.
#
# Safe to run again: both keys are reused, never replaced. Replacing one strands every installed
# copy on what it shipped with.
# Usage: sh app/Scripts/signing-keys.sh    (then commit the two changed files in a pull request)
set -eu
cd "$(dirname "$0")/.."
REPO="Echarnus/Cellar"
SERVICE="it.clercq.cellar.release.profiles"
SWIFT_FILE="Packages/CellarData/Sources/CellarData/Library/ProfileUpdates.swift"
# A Nix/devenv shell exports SDKROOT/DEVELOPER_DIR for a non-matching SDK, and `swift` then fails
# with "this SDK is not supported by the compiler". sparkle-keys.sh clears them only for itself, so
# clear them here too, before this script runs `swift` for the game-database key.
. Scripts/select-xcode.sh

command -v gh >/dev/null 2>&1 || { echo "Needs the GitHub CLI: brew install gh && gh auth login"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Sign the GitHub CLI in first: gh auth login"; exit 1; }
[ -f "$SWIFT_FILE" ] || { echo "$SWIFT_FILE not found — run from a Cellar checkout"; exit 1; }

# 1. Updates.
sh Scripts/sparkle-keys.sh

# 2. The game database. The keychain copy is the source of truth; GitHub only ever receives it.
if KEY="$(security find-generic-password -s "$SERVICE" -a cellar -w 2>/dev/null)"; then
  echo "Reusing the game-database key already in your login keychain."
else
  OUT="$(swift Scripts/profiles-bundle.swift --generate-key)"
  KEY="$(printf '%s\n' "$OUT" | sed -n 's/^PROFILES_SIGNING_KEY[^:]*: *//p')"
  [ -n "$KEY" ] || { echo "profiles-bundle.swift did not print a key"; exit 1; }
  # -w on stdin is not supported by `security`, so the key is an argument for this one call; it
  # is a local process of the maintainer's own, gone the moment it returns.
  security add-generic-password -s "$SERVICE" -a cellar -l "Cellar — game database signing key" -w "$KEY"
  echo "Made a game-database key and saved it in your login keychain ($SERVICE)."
fi
PUBLIC="$(printf '%s' "$KEY" | swift Scripts/profiles-bundle.swift --public-key)"
[ -n "$PUBLIC" ] || { echo "Could not derive the public key"; exit 1; }

gh api --silent -X PUT "repos/$REPO/environments/release"
printf '%s' "$KEY" | gh secret set PROFILES_SIGNING_KEY --repo "$REPO" --env release
unset KEY
echo "Stored PROFILES_SIGNING_KEY in the release environment of $REPO."

# The public half, compiled into every build from now on.
# Written through a temporary file, not `sed -i`: BSD sed wants `-i ''` and GNU sed (a Nix shell's)
# reads that '' as a file name, so no single `-i` spelling works on both.
sed "s|public static let publicKey = \"[^\"]*\"|public static let publicKey = \"$PUBLIC\"|" "$SWIFT_FILE" > "$SWIFT_FILE.tmp"
mv "$SWIFT_FILE.tmp" "$SWIFT_FILE"
grep -q "publicKey = \"$PUBLIC\"" "$SWIFT_FILE" || { echo "Could not write the public key into $SWIFT_FILE"; exit 1; }
echo "Wrote the game-database public key into $SWIFT_FILE."

echo
echo "Done. Commit these two files on a branch and open a pull request:"
echo "  app/Resources/sparkle-public-key"
echo "  app/$SWIFT_FILE"
echo "From the next release on, Cellar updates itself and its game database."
