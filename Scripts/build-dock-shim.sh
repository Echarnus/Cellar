#!/bin/sh
# Build the Dock shim Cellar inserts into a bottle's storefront client (see Shim/cellar-dock-shim.c).
# Universal, because a Wine runner may be x86_64 (Rosetta) or arm64 — the shim has to match the
# process it is inserted into, not the Mac it was built on.
# Usage: Scripts/build-dock-shim.sh [output path]   (default: .build/cellar-dock-shim.dylib)
set -e
cd "$(dirname "$0")/.."
# A Nix/devenv shell may export DEVELOPER_DIR/SDKROOT pointing at a non-macOS SDK; use Xcode's.
unset DEVELOPER_DIR SDKROOT

OUT="${1:-.build/cellar-dock-shim.dylib}"
mkdir -p "$(dirname "$OUT")"
# Absolute path: a devenv shell puts a Nix clang first on PATH, and that one cannot see the macOS SDK.
/usr/bin/xcrun clang -arch x86_64 -arch arm64 -mmacosx-version-min=13.0 \
  -O2 -Wall -Wextra -dynamiclib -install_name @rpath/cellar-dock-shim.dylib \
  -lobjc -o "$OUT" Shim/cellar-dock-shim.c
echo "Built $OUT ($(lipo -archs "$OUT"))"
