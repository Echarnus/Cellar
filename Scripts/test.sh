#!/bin/sh
# Run Cellar's test suite.
#
# Why a script rather than a bare `swift test`:
#
#   1. A Nix/devenv shell exports DEVELOPER_DIR/SDKROOT pointing at a non-macOS SDK, which makes
#      the Swift build fail or link the wrong SDK (see AGENTS.md). Every other script here unsets
#      both for the same reason.
#   2. Unsetting DEVELOPER_DIR is not enough for the *tests*: swift-testing ships as a framework
#      inside the developer directory, and with DEVELOPER_DIR unset the toolchain falls back to
#      `xcode-select -p` — which on this machine is the Nix SDK, where no Testing.framework exists,
#      and every test file fails with "no such module 'Testing'".
#
# So the build rule is "unset it", and the test rule is "point it at a developer directory that
# actually has swift-testing in it". This script finds one.
set -e

cd "$(dirname "$0")/.."

unset SDKROOT

# Prefer whatever DEVELOPER_DIR the caller set *if* it has swift-testing; otherwise find one that
# does. Checking for the framework rather than trusting a path keeps this working on a machine with
# Xcode, with only the Command Line Tools, or with both.
DEVELOPER_DIR_FOUND=""
FRAMEWORKS=""
INTEROP=""
for candidate in \
    "$DEVELOPER_DIR" \
    "/Applications/Xcode.app/Contents/Developer" \
    "/Library/Developer/CommandLineTools"
do
    [ -n "$candidate" ] || continue
    if [ -d "$candidate/Library/Developer/Frameworks/Testing.framework" ]; then
        DEVELOPER_DIR_FOUND="$candidate"
        FRAMEWORKS="$candidate/Library/Developer/Frameworks"
        # Testing.framework itself loads @rpath/lib_TestingInterop.dylib, which sits one level up
        # beside it rather than inside it — so it needs its own rpath or the bundle fails to dlopen.
        INTEROP="$candidate/Library/Developer/usr/lib"
        break
    fi
done

if [ -z "$DEVELOPER_DIR_FOUND" ]; then
    echo "error: no developer directory with swift-testing was found." >&2
    echo "       Install the Xcode Command Line Tools (xcode-select --install)," >&2
    echo "       or set DEVELOPER_DIR to a toolchain that has Testing.framework." >&2
    exit 1
fi

export DEVELOPER_DIR="$DEVELOPER_DIR_FOUND"

# SwiftPM does not add the developer directory's framework search path by itself here, so `import
# Testing` fails even once DEVELOPER_DIR is right. Passing it explicitly is what makes the suite
# compile; the rpath is what lets the built test bundle find the framework at run time.
echo "==> DEVELOPER_DIR=$DEVELOPER_DIR"
echo "==> swift test $*"
echo

swift test \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xlinker -F -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$INTEROP" \
    "$@"

status=0

sheet_dir=".build/ui-snapshots"
if [ -d "$sheet_dir" ]; then
    echo
    echo "==> Rendered snapshots (open these instead of launching the app):"
    for png in "$sheet_dir"/*.png; do
        [ -e "$png" ] || continue
        echo "    $(pwd)/$png"
    done
fi

exit $status
