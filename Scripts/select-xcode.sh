# shellcheck shell=sh
# Sourced (not run) by install-app.sh and package.sh to pick the toolchain that builds the app.
#
# A Nix/devenv shell may export DEVELOPER_DIR/SDKROOT pointing at a non-macOS SDK, so both are
# cleared and `xcode-select -p` decides. When that is the Command Line Tools, the SwiftUI app cannot
# build — they ship no SwiftUI macro plugins, so `@State` fails with "SwiftUIMacros.StateMacro could
# not be found". Then a full Xcode is used if one is installed and its toolchain actually runs (an
# unaccepted licence makes every invocation fail). Anywhere xcode-select already points at an Xcode —
# GitHub's macOS runners included — nothing changes.
unset DEVELOPER_DIR SDKROOT
case "$(xcode-select -p 2>/dev/null)" in
  */CommandLineTools*)
    # Xcode-beta.app also matches Xcode-*.app; the glob covers it (and versioned names from `xcodes`).
    for candidate in /Applications/Xcode.app /Applications/Xcode-*.app; do
      dir="$candidate/Contents/Developer"
      [ -d "$dir" ] || continue
      if DEVELOPER_DIR="$dir" swift --version >/dev/null 2>&1; then
        DEVELOPER_DIR="$dir"
        export DEVELOPER_DIR
        echo "==> building with $candidate (xcode-select points at the Command Line Tools)"
        break
      fi
      echo "==> skipping $candidate (toolchain unusable — accept its licence: sudo xcodebuild -license accept)"
    done
    if [ -z "${DEVELOPER_DIR:-}" ]; then
      echo "==> no usable Xcode found; the Command Line Tools alone cannot build the SwiftUI app." >&2
      echo "    Install Xcode, or point xcode-select at it: sudo xcode-select -s /Applications/Xcode.app" >&2
      exit 1
    fi ;;
esac
