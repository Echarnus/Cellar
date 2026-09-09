#!/bin/sh
# Run Cellar's test suite.
#
#   sh Scripts/test.sh                 # unit tests only — fast, hermetic, what CI runs
#   sh Scripts/test.sh --integration   # + the Wine tiers: real runner, real prefix, real Windows exe
#   sh Scripts/test.sh --filter Store  # pass anything else straight through to `swift test`
#
# Two environment problems this exists to solve:
#
#  1. A Nix/devenv shell exports DEVELOPER_DIR/SDKROOT pointing at a non-macOS SDK. The rest of the
#     repo just unsets them (see Scripts/install-app.sh), but tests need more than an SDK: swift
#     testing lives in Testing.framework, which only a full Xcode ships. So this picks a developer
#     directory that actually has it rather than merely unsetting.
#  2. The integration tiers are opt-in, because they install runners and start Windows processes.
set -e

cd "$(dirname "$0")/.."

unset SDKROOT

# A developer directory is usable for tests only if it carries Testing.framework.
has_testing() {
    [ -d "$1/Platforms/MacOSX.platform/Developer/Library/Frameworks/Testing.framework" ]
}

if ! has_testing "${DEVELOPER_DIR:-/nonexistent}"; then
    unset DEVELOPER_DIR
    for candidate in \
        "$(xcode-select -p 2>/dev/null || true)" \
        /Applications/Xcode.app/Contents/Developer \
        /Applications/Xcode-beta.app/Contents/Developer
    do
        if [ -n "$candidate" ] && has_testing "$candidate"; then
            DEVELOPER_DIR="$candidate"
            export DEVELOPER_DIR
            break
        fi
    done
fi

if [ -z "${DEVELOPER_DIR:-}" ]; then
    echo "error: no Xcode with Testing.framework found." >&2
    echo "       The Command Line Tools alone cannot build the test targets." >&2
    echo "       Install Xcode, or point DEVELOPER_DIR at one." >&2
    exit 1
fi

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
    echo "==> Unit tests only. Add --integration to run the Wine tiers."
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

# --no-parallel: the suites share one sandboxed Cellar home, and a few of them set an environment
# variable to prove Cellar scrubs it. Serial is also plenty fast — the unit tests are sub-second.
# shellcheck disable=SC2086
swift test --no-parallel $ARGS
STATUS=$?

# Keep the sandbox when something failed — a Wine log in there is usually the reason.
if [ "$STATUS" = "0" ]; then
    rm -rf "$CELLAR_TEST_ROOT"
else
    echo "==> Test sandbox kept for inspection: $CELLAR_TEST_ROOT"
fi
exit $STATUS
