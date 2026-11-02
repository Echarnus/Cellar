#!/bin/sh
# Build WineForge's wineserver with Cellar's patches (app/RunnerPatches/wineforge/) applied.
#
# Only the server is built: it is a plain x86_64 Mach-O that links libSystem alone, and the fixes it
# carries do not touch the client/server protocol, so it drops into the matching WineForge runner
# unchanged. The source is pinned to an exact commit, and the build fails if the checkout is not it.
#
# Usage: Scripts/build-wineserver.sh [output path]   (default: .build/wineserver/wineserver)
# Needs: Xcode or the Command Line Tools, Rosetta, git, and bison >= 3 on PATH (Homebrew's).
set -eu
cd "$(dirname "$0")/.."
unset DEVELOPER_DIR SDKROOT

WINEFORGE_REPO="https://github.com/Alien4042x/WineForge.git"
WINEFORGE_TAG="0.6.0.8"
WINEFORGE_COMMIT="9a445e947d0d7cad140f31c77cb94fb2057a4882"

APP_DIR="$(pwd)"
OUT="${1:-.build/wineserver/wineserver}"
case "$OUT" in /*) ;; *) OUT="$APP_DIR/$OUT" ;; esac
WORK="$APP_DIR/.build/wineserver-src"

rm -rf "$WORK"
mkdir -p "$WORK" "$(dirname "$OUT")"
git clone --quiet --depth 1 --branch "$WINEFORGE_TAG" "$WINEFORGE_REPO" "$WORK/src"
actual="$(git -C "$WORK/src" rev-parse HEAD)"
if [ "$actual" != "$WINEFORGE_COMMIT" ]; then
  echo "WineForge $WINEFORGE_TAG is $actual, expected $WINEFORGE_COMMIT; refusing to build." >&2
  exit 1
fi

for patch in "$APP_DIR"/RunnerPatches/wineforge/*.patch; do
  echo "Applying $(basename "$patch")"
  git -C "$WORK/src" apply --verbose "$patch"
done

mkdir -p "$WORK/build"
cd "$WORK/build"
# The runner's wineserver is x86_64 (it runs under Rosetta), so configure and build as x86_64.
# Nothing but the server is built, so every optional library is left out.
arch -x86_64 /bin/sh "$WORK/src/configure" \
  --build=x86_64-apple-darwin \
  --enable-win64 \
  --disable-tests \
  --without-mingw \
  --without-x \
  --without-freetype \
  --without-gnutls \
  --without-gstreamer \
  --without-ffmpeg \
  --without-sdl \
  --without-vulkan \
  --without-opencl \
  --without-pcap \
  --without-cups \
  --without-usb \
  --without-capi \
  --without-gphoto \
  --without-sane \
  --without-krb5 \
  --without-gssapi \
  --without-netapi \
  --without-pcsclite \
  > configure.log 2>&1 || { tail -40 configure.log >&2; exit 1; }
arch -x86_64 make -j"$(sysctl -n hw.ncpu)" server/wineserver > make.log 2>&1 || { tail -60 make.log >&2; exit 1; }

cp server/wineserver "$OUT"
codesign --force --sign - "$OUT"
echo "Built $OUT"
file "$OUT"
otool -L "$OUT"
shasum -a 256 "$OUT"
