#!/bin/sh
# Build Cellar's own SDL: SDL 3 plus sdl2-compat, which presents it as the libSDL2-2.0.0.dylib that
# the runner's Wine loads by name. Wine's input layer (winebus) hands a game's force-feedback
# effects to SDL; the runner's own SDL can only send them through macOS's ForceFeedback plug-ins,
# which no wheel maker ships for Apple Silicon. SDL 3.4 talks to the wheel over USB itself instead
# (HIDAPI), and Cellar's own patches add the wheels SDL has no driver for (Shim/sdl/). See
# docs/ARCHITECTURE.md → Controllers and racing wheels.
#
# Universal, like the Dock shim: the runner may be x86_64 (Rosetta) or arm64. Sources are pinned by
# version and SHA-256 and fetched from libsdl.org's GitHub releases; patches in Shim/sdl/*.patch are
# applied to SDL 3 in name order. The result is cached against all of that.
# Usage: Scripts/build-sdl.sh [output directory]   (default: .build/sdl)
set -eu
cd "$(dirname "$0")/.."
# A Nix/devenv shell may export DEVELOPER_DIR/SDKROOT pointing at a non-macOS SDK; use Xcode's.
unset DEVELOPER_DIR SDKROOT

SDL3_VERSION=3.4.18
SDL3_SHA256=9c75cf16330322c217dedd2e0609f1124f1b54b8633e763467b4684d0f4334a3
COMPAT_VERSION=2.32.74
COMPAT_SHA256=ec68abde77e2e459c8abc4f9587b8976b5d2a657b2bfda2fb3a079b0f8924588

OUT="${1:-.build/sdl}"
# Always built into one cache directory and copied to OUT, so the CI test step and packaging, which
# ask for different outputs, build it once.
CACHE=".build/sdl"
WORK=".build/sdl-work"
mkdir -p "$OUT" "$CACHE" "$WORK"
OUT="$(cd "$OUT" && pwd)"
CACHE="$(cd "$CACHE" && pwd)"

# copy_out: hand the cached build to the caller's directory.
copy_out() {
  if [ "$OUT" != "$CACHE" ]; then
    rm -rf "$OUT"
    mkdir -p "$OUT"
    cp "$CACHE"/libSDL2-2.0.0.dylib "$CACHE"/libSDL3.dylib "$CACHE"/LICENSE-SDL.txt "$OUT"/
  fi
}

# Everything the output depends on, so an unchanged input is not rebuilt (it takes minutes).
STAMP="sdl3=$SDL3_VERSION:$SDL3_SHA256 compat=$COMPAT_VERSION:$COMPAT_SHA256 patches=$(cat Shim/sdl/*.patch Shim/sdl/tests/*.c 2>/dev/null | shasum -a 256 | cut -c1-16)"
if [ -f "$CACHE/libSDL2-2.0.0.dylib" ] && [ -f "$CACHE/libSDL3.dylib" ] && [ "$(cat "$WORK/stamp" 2>/dev/null)" = "$STAMP" ]; then
  copy_out
  echo "Cellar's SDL is up to date ($OUT)"
  exit 0
fi
rm -f "$WORK/stamp"

# fetch <url> <sha256> <file>
fetch() {
  if [ ! -f "$3" ] || [ "$(shasum -a 256 "$3" | cut -d' ' -f1)" != "$2" ]; then
    curl -fsSL --retry 3 -o "$3.part" "$1"
    mv "$3.part" "$3"
  fi
  actual="$(shasum -a 256 "$3" | cut -d' ' -f1)"
  if [ "$actual" != "$2" ]; then
    echo "error: $3 has SHA-256 $actual, expected $2 — refusing to build from it" >&2
    rm -f "$3"
    exit 1
  fi
}

fetch "https://github.com/libsdl-org/SDL/releases/download/release-$SDL3_VERSION/SDL3-$SDL3_VERSION.tar.gz" \
  "$SDL3_SHA256" "$WORK/SDL3-$SDL3_VERSION.tar.gz"
fetch "https://github.com/libsdl-org/sdl2-compat/releases/download/release-$COMPAT_VERSION/sdl2-compat-$COMPAT_VERSION.tar.gz" \
  "$COMPAT_SHA256" "$WORK/sdl2-compat-$COMPAT_VERSION.tar.gz"

rm -rf "$WORK/src" "$WORK/build" "$WORK/prefix"
mkdir -p "$WORK/src"
tar -xzf "$WORK/SDL3-$SDL3_VERSION.tar.gz" -C "$WORK/src"
tar -xzf "$WORK/sdl2-compat-$COMPAT_VERSION.tar.gz" -C "$WORK/src"
SDL3_SRC="$WORK/src/SDL3-$SDL3_VERSION"
COMPAT_SRC="$WORK/src/sdl2-compat-$COMPAT_VERSION"

for p in Shim/sdl/*.patch; do
  [ -f "$p" ] || continue
  echo "Applying $p"
  patch -s -p1 -d "$SDL3_SRC" < "$p"
done

# Absolute compiler paths: a devenv shell puts a Nix clang first on PATH, which cannot see the SDK.
COMMON="-DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_OSX_ARCHITECTURES=x86_64;arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DCMAKE_OBJC_COMPILER=/usr/bin/clang"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "Building SDL $SDL3_VERSION (universal)…"
# shellcheck disable=SC2086 # COMMON is a list of arguments
cmake -S "$SDL3_SRC" -B "$WORK/build/sdl3" $COMMON -DCMAKE_INSTALL_PREFIX="$PWD/$WORK/prefix" \
  -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST_LIBRARY=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
  -DSDL_HIDAPI=ON -DSDL_HIDAPI_JOYSTICK=ON >/dev/null
cmake --build "$WORK/build/sdl3" -j "$JOBS"
cmake --install "$WORK/build/sdl3" >/dev/null

echo "Building sdl2-compat $COMPAT_VERSION (universal)…"
# shellcheck disable=SC2086
cmake -S "$COMPAT_SRC" -B "$WORK/build/compat" $COMMON -DCMAKE_PREFIX_PATH="$PWD/$WORK/prefix" \
  -DSDL2COMPAT_TESTS=OFF -DSDL2COMPAT_INSTALL=OFF >/dev/null
cmake --build "$WORK/build/compat" -j "$JOBS"

COMPAT_LIB="$(find "$WORK/build/compat" -maxdepth 2 -name 'libSDL2-2.0.0.dylib' -type f | head -n 1)"
SDL3_LIB="$WORK/prefix/lib/libSDL3.0.dylib"
[ -n "$COMPAT_LIB" ] || { echo "error: sdl2-compat produced no libSDL2-2.0.0.dylib" >&2; exit 1; }
# sdl2-compat looks for "@loader_path/libSDL3.dylib" first, so the two travel side by side.
cp "$COMPAT_LIB" "$CACHE/libSDL2-2.0.0.dylib"
cp "$SDL3_LIB" "$CACHE/libSDL3.dylib"
cp "$SDL3_SRC/LICENSE.txt" "$CACHE/LICENSE-SDL.txt"

# What Wine needs from it: both architectures, and the SDL 2 haptic API winebus binds to.
for lib in "$CACHE/libSDL2-2.0.0.dylib" "$CACHE/libSDL3.dylib"; do
  archs="$(lipo -archs "$lib")"
  case "$archs" in *x86_64*arm64*|*arm64*x86_64*) ;; *) echo "error: $lib is $archs, not universal" >&2; exit 1 ;; esac
done
for symbol in SDL_Init SDL_JoystickOpen SDL_HapticOpenFromJoystick SDL_HapticNewEffect SDL_HapticRunEffect SDL_HapticSetGain; do
  nm -gU "$CACHE/libSDL2-2.0.0.dylib" | grep -q " _$symbol\$" \
    || { echo "error: libSDL2-2.0.0.dylib does not export $symbol" >&2; exit 1; }
done
nm -gU "$CACHE/libSDL3.dylib" | grep -q " _SDL_OpenHapticFromJoystick\$" \
  || { echo "error: libSDL3.dylib has no haptic support" >&2; exit 1; }
# Cellar's wheel drivers are inside it (private symbols, so not -g).
for driver in Fanatec Thrustmaster; do
  nm "$CACHE/libSDL3.dylib" | grep -q " _Cellar${driver}_Create\$" \
    || { echo "error: libSDL3.dylib was built without Cellar's $driver driver" >&2; exit 1; }
done

# And that it starts: load it the way winebus does (dlopen by path), bring up the joystick and
# haptic subsystems, and check sdl2-compat found the SDL 3 beside it. Both slices, where the Mac can
# run x86_64 at all.
cat > "$WORK/smoke.c" <<'SMOKE'
#include <dlfcn.h>
#include <stdio.h>
typedef struct { unsigned char major, minor, patch; } version_t;
int main(int argc, char **argv) {
    if (argc < 2) return 2;
    void *sdl = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!sdl) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }
    int (*init)(unsigned) = (int (*)(unsigned))dlsym(sdl, "SDL_Init");
    void (*get_version)(version_t *) = (void (*)(version_t *))dlsym(sdl, "SDL_GetVersion");
    const char *(*get_error)(void) = (const char *(*)(void))dlsym(sdl, "SDL_GetError");
    void (*quit)(void) = (void (*)(void))dlsym(sdl, "SDL_Quit");
    if (!init || !get_version || !get_error || !quit) { fprintf(stderr, "missing SDL 2 entry points\n"); return 1; }
    /* SDL_INIT_JOYSTICK | SDL_INIT_HAPTIC, as winebus asks for them. */
    if (init(0x00000200u | 0x00001000u) != 0) { fprintf(stderr, "SDL_Init: %s\n", get_error()); return 1; }
    version_t v; get_version(&v);
    printf("SDL %d.%d.%d (sdl2-compat) started\n", v.major, v.minor, v.patch);
    quit();
    return 0;
}
SMOKE
/usr/bin/clang -arch x86_64 -arch arm64 -mmacosx-version-min=13.0 -o "$WORK/smoke" "$WORK/smoke.c"
"$WORK/smoke" "$CACHE/libSDL2-2.0.0.dylib"
if /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  /usr/bin/arch -x86_64 "$WORK/smoke" "$CACHE/libSDL2-2.0.0.dylib"
else
  echo "Rosetta not available: x86_64 slice built and checked, not started"
fi

# Cellar's drivers, tested against this exact SDL on a fake wheel base that records every command:
# the init sequence, the encoding, the strength cap and stopping on close. Both slices.
DRIVERS="$SDL3_SRC/src/haptic/darwin"
for driver in fanatec thrustmaster; do
  /usr/bin/clang -arch x86_64 -arch arm64 -mmacosx-version-min=13.0 -std=c99 -Wall -Wextra -Werror \
    -Wno-unused-parameter -DCELLAR_FFB_STANDALONE -I"$DRIVERS" -I"$WORK/prefix/include" \
    "$DRIVERS/SDL_cellar_$driver.c" "Shim/sdl/tests/test_$driver.c" \
    -L"$WORK/prefix/lib" -lSDL3 -Wl,-rpath,"$PWD/$WORK/prefix/lib" -o "$WORK/test_$driver"
  "$WORK/test_$driver"
  if /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
    /usr/bin/arch -x86_64 "$WORK/test_$driver"
  fi
done

echo "$STAMP" > "$WORK/stamp"
copy_out
echo "Built Cellar's SDL into $OUT ($(lipo -archs "$OUT/libSDL3.dylib"))"
