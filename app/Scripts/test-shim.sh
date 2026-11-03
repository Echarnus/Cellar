#!/bin/sh
# Test the C in Shim/ that a Swift test cannot reach: Shim/cellar-recvtos.c, which hands Wine a UDP
# packet's TOS byte so Steam's networking does not assert (tests/Shim/recvtos-test.c says how).
# Runs the check twice — through the built shim, and against plain libc to prove macOS still labels
# the byte the way the shim expects.
# Usage: Scripts/test-shim.sh [shim path]   (default: .build/cellar-dock-shim.dylib, built if missing)
set -eu
cd "$(dirname "$0")/.."
# A Nix/devenv shell may export DEVELOPER_DIR/SDKROOT pointing at a non-macOS SDK; use Xcode's.
unset DEVELOPER_DIR SDKROOT

SHIM="${1:-.build/cellar-dock-shim.dylib}"
[ -f "$SHIM" ] || sh Scripts/build-dock-shim.sh "$SHIM"
OUT=".build/shim-tests"
mkdir -p "$OUT"
SHIM_DIR="$(cd "$(dirname "$SHIM")" && pwd)"

/usr/bin/xcrun clang -arch x86_64 -arch arm64 -O2 -Wall -Wextra -DCELLAR_RECVTOS_NO_INTERPOSE \
  -o "$OUT/recvtos-plain" tests/Shim/recvtos-test.c Shim/cellar-recvtos.c
/usr/bin/xcrun clang -arch x86_64 -arch arm64 -O2 -Wall -Wextra \
  -o "$OUT/recvtos-shim" tests/Shim/recvtos-test.c "$SHIM" -Wl,-rpath,"$SHIM_DIR"

"$OUT/recvtos-plain"
CELLAR_TEST_SHIM_LOADED=1 "$OUT/recvtos-shim"
# A runner may be x86_64 under Rosetta: check that slice too where Rosetta is installed.
if /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  CELLAR_TEST_SHIM_LOADED=1 /usr/bin/arch -x86_64 "$OUT/recvtos-shim"
fi
