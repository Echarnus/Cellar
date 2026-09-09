#!/bin/sh
# Run Cellar's test suite.
#
#   sh Scripts/test.sh                 # unit + hermetic tiers — fast, what CI runs
#   sh Scripts/test.sh --integration   # + the Wine tiers: real runner, real prefix, real Windows exe
#   sh Scripts/test.sh --filter Store  # anything else is passed straight through to `swift test`
#
# Three environment problems this exists to solve:
#
#  1. A Nix/devenv shell exports DEVELOPER_DIR/SDKROOT pointing at a non-macOS SDK. The rest of the
#     repo just unsets them (see Scripts/install-app.sh), but unsetting is not enough for tests:
#     swift-testing lives in Testing.framework, inside a developer directory, and with DEVELOPER_DIR
#     unset the toolchain falls back to `xcode-select -p` — the Nix SDK, which has none. So this
#     picks a developer directory that actually carries the framework rather than merely unsetting.
#
#     Note the two layouts. A full Xcode keeps it under Platforms/MacOSX.platform/…; the Command
#     Line Tools keep it under Library/Developer/Frameworks. **The Command Line Tools alone are
#     enough** — checking only the Xcode path is what previously made the suite look unbuildable.
#
#  2. SwiftPM does not add that framework search path by itself, so `import Testing` fails even once
#     DEVELOPER_DIR is right. It has to be passed explicitly, along with rpaths — including one for
#     lib_TestingInterop.dylib, which Testing.framework loads and which sits beside it, not inside.
#
#  3. The integration tiers are opt-in, because they install runners and start Windows processes.
set -e

cd "$(dirname "$0")/.."

unset SDKROOT

# A developer directory is usable only if it really carries Testing.framework — in either layout.
testing_framework_in() {
    if [ -d "$1/Library/Developer/Frameworks/Testing.framework" ]; then
        echo "$1/Library/Developer/Frameworks"
    elif [ -d "$1/Platforms/MacOSX.platform/Developer/Library/Frameworks/Testing.framework" ]; then
        echo "$1/Platforms/MacOSX.platform/Developer/Library/Frameworks"
    fi
}

# Having the framework is not enough — the toolchain has to actually run. An installed Xcode whose
# licence has never been accepted carries Testing.framework and then refuses every invocation with
# "You have not agreed to the Xcode license agreements", so each candidate is probed before it is
# chosen. The Command Line Tools need no licence, which is why they are a fine answer here.
FRAMEWORKS=""
for candidate in \
    "$DEVELOPER_DIR" \
    "/Applications/Xcode.app/Contents/Developer" \
    "/Applications/Xcode-beta.app/Contents/Developer" \
    "/Library/Developer/CommandLineTools"
do
    [ -n "$candidate" ] || continue
    found="$(testing_framework_in "$candidate")"
    [ -n "$found" ] || continue
    if ! DEVELOPER_DIR="$candidate" swift --version >/dev/null 2>&1; then
        echo "==> skipping $candidate (toolchain unusable — an unaccepted Xcode licence does this)"
        continue
    fi
    DEVELOPER_DIR="$candidate"
    FRAMEWORKS="$found"
    export DEVELOPER_DIR
    break
done

if [ -z "$FRAMEWORKS" ]; then
    echo "error: no usable developer directory with swift-testing was found." >&2
    echo "       Install the Xcode Command Line Tools (xcode-select --install), or if you have" >&2
    echo "       Xcode, accept its licence with: sudo xcodebuild -license accept" >&2
    exit 1
fi

# Testing.framework loads @rpath/lib_TestingInterop.dylib, which lives beside the framework
# directory rather than inside it, so it needs an rpath of its own or the bundle fails to dlopen.
INTEROP="$DEVELOPER_DIR/Library/Developer/usr/lib"

INTEGRATION=0
ARGS=""
for arg in "$@"; do
    case "$arg" in
        --integration) INTEGRATION=1 ;;
        *) ARGS="$ARGS $arg" ;;
    esac
done

if [ "$INTEGRATION" = "1" ]; then
    CELLAR_IT=1
    export CELLAR_IT
    echo "==> Test run WITH the Wine integration tiers (CELLAR_IT=1)"
    echo "    Runner:  ${CELLAR_IT_RUNNER:-whatever is installed, else the catalog default}"
    echo "    Game:    ${CELLAR_IT_GAME_URL:-winemine.exe from the runner itself}"
else
    echo "==> Unit + hermetic tiers. Add --integration to run the Wine tiers."
fi

# Hand the test process a throwaway Cellar installation.
#
# The suites can create this themselves, but doing it here means the environment is already correct
# before a single test runs — so nothing ever calls setenv() while another test is reading it, and
# a run can never reach the player's real bottles, sign-ins or ~/Applications.
CELLAR_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cellar-tests.XXXXXXXX")"
CELLAR_HOME="$CELLAR_TEST_ROOT/home"
CELLAR_PROFILES_DIR="$CELLAR_TEST_ROOT/profiles"
CELLAR_APPLICATIONS_DIR="$CELLAR_TEST_ROOT/Applications"
export CELLAR_TEST_ROOT CELLAR_HOME CELLAR_PROFILES_DIR CELLAR_APPLICATIONS_DIR
mkdir -p "$CELLAR_HOME" "$CELLAR_PROFILES_DIR" "$CELLAR_APPLICATIONS_DIR"

echo "==> DEVELOPER_DIR=$DEVELOPER_DIR"
echo "==> CELLAR_HOME=$CELLAR_HOME (throwaway)"
echo

# --no-parallel: the suites share one sandboxed Cellar home, and a few of them set an environment
# variable to prove Cellar scrubs it. Serial is also plenty fast — the whole run is about a second.
set +e
# shellcheck disable=SC2086
swift test --no-parallel \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xlinker -F -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$INTEROP" \
    $ARGS
STATUS=$?
set -e

sheet_dir=".build/ui-snapshots"
if [ -d "$sheet_dir" ]; then
    echo
    echo "==> Rendered snapshots (open these instead of launching the app):"
    for png in "$sheet_dir"/*.png; do
        [ -e "$png" ] || continue
        echo "    $(pwd)/$png"
    done
fi

# Keep the sandbox when something failed — a Wine log in there is usually the reason.
if [ "$STATUS" = "0" ]; then
    rm -rf "$CELLAR_TEST_ROOT"
else
    echo "==> Test sandbox kept for inspection: $CELLAR_TEST_ROOT"
fi
exit $STATUS
