#!/bin/sh
# Prove a test run left the player's real Wine runners exactly as it found them (#204).
#
#   sh Scripts/runner-guard.sh snapshot <file>    # record the runners' fingerprint
#   sh Scripts/runner-guard.sh compare  <file>    # fail, naming each file, if anything changed
#
# The fingerprint is the SHA-256 of every file a runner is started from: everything in a `bin`
# folder, plus Wine's Unix-side `wine` loader and `ntdll.so`. The same files RunnerIntegrity and
# CellarSandbox.Fingerprint guard. #190 is the failure this catches: a test wrote a fake `wine`
# into the real WineForge runner, and every Play afterwards started nothing.
#
# CELLAR_REAL_HOME points it at another installation (the tests of this script use that). It is
# deliberately not CELLAR_HOME, which a test run points at its throwaway sandbox.
set -eu

real="${CELLAR_REAL_HOME:-$HOME/Library/Application Support/Cellar}"
runners="$real/runners"

fingerprint() {
    if [ ! -d "$runners" ]; then
        return 0
    fi
    # Paths are printed relative to the runners folder so the file reads the same on any machine.
    ( cd "$runners" && find . -type f \( -path '*/bin/*' -o -path '*/x86_64-unix/wine' \
        -o -path '*/x86_64-unix/ntdll.so' \) ! -path '*/bin/*/*' -exec shasum -a 256 {} + ) | LC_ALL=C sort -k 2
}

if [ "$#" -ne 2 ]; then
    echo "usage: $0 snapshot|compare <file>" >&2
    exit 2
fi

case "$1" in
    snapshot)
        fingerprint > "$2"
        ;;
    compare)
        now="$(mktemp "${TMPDIR:-/tmp}/cellar-runner-guard.XXXXXXXX")"
        trap 'rm -f "$now"' EXIT
        fingerprint > "$now"
        if cmp -s "$2" "$now"; then
            exit 0
        fi
        echo "error: this run changed the real Wine runners in $runners:" >&2
        # A line only in the snapshot was changed or removed; only now, changed or added.
        diff "$2" "$now" | sed -n 's/^[<>] [0-9a-f]*  \.\//    /p' | LC_ALL=C sort -u >&2 || true
        echo "       A test must never write there. Repair it from the app (Play repairs a damaged" >&2
        echo "       runtime by itself), and find the test that wrote outside its sandbox." >&2
        exit 1
        ;;
    *)
        echo "usage: $0 snapshot|compare <file>" >&2
        exit 2
        ;;
esac
