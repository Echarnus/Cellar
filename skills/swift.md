# Skill: Swift, SwiftUI & AppKit in Cellar

Best practices for `Sources/**`. Portable guide; Claude's auto-discovered copy is
`.claude/skills/cellar-swift/SKILL.md`. Read [`../AGENTS.md`](../AGENTS.md) first — and
[`ux.md`](ux.md) before touching anything a player sees. This file covers the *mechanics*; `ux.md`
sets the bar the result is judged against.

## Build

Always release-build with the SDK vars unset, or a Nix/devenv shell links the wrong SDK:

```sh
env -u DEVELOPER_DIR -u SDKROOT swift build -c release
```

The package is Swift-tools 6.0 but compiles in **Swift 5 language mode** (`swiftLanguageModes:
[.v5]`) — a synchronous CLI doesn't need strict-concurrency overhead yet. Don't add `async`/actor
machinery unless a target genuinely needs it.

## Architecture rules

- **Per-store behaviour belongs in `GameStore.descriptor`** (`Store.swift`), not in a `switch` inside
  a view or a command. If a view needs to know that Battle.net's installer isn't silent, that fact
  should reach it as data.
- **All logic lives in `CellarKit`.** The CLI (`Sources/cellar`) and the app (`Sources/CellarApp`)
  are thin. Never duplicate engine logic in a command or a view — add it to CellarKit and call it.
- **The GUI drives the CLI as a subprocess** for side-effecting actions (setup, install, launch), so
  it inherits every tested path (silent Steam, the launch auto-retry, close-on-exit). Read-only state
  comes from `Game.summaries()`. Don't reimplement an action inside the app.
- **CLI:** one file per command group under `Commands/`, ArgumentParser, small `struct` commands.
- **CellarKit never prints.** Terminal output is the CLI's job (and is UI — see [`ux.md`](ux.md)).
  A library function that `print`s cannot be reused by the app, which renders the same information.
  Return values or `throw`; let the front-end word it.

## Running subprocesses (load-bearing — Cellar is mostly a process driver)

Nearly everything Cellar does is a `Process`: wine, wineserver, curl, DepotDownloader, the `cellar`
CLI itself. Two traps, one of which is live in the codebase today.

- **Draining two pipes sequentially can deadlock.** `Shell.run` sets a `Pipe` on both stdout and
  stderr and then does `readDataToEndOfFile()` on stdout *and only afterwards* on stderr. A pipe
  buffer is finite (~64 KB): if the child fills **stderr** while the parent is still blocked reading
  **stdout**, the child blocks on write, never closes stdout, and both sides wait forever. `Shell`
  documents the assumption that its outputs are small (version strings, paths) — that assumption is
  the only thing keeping it safe.
  **So: never route a chatty command through `Shell.run`.** Wine is exactly that kind of command —
  `WINEDEBUG` output, D3DMetal and CEF noise all land on stderr. Use one of:
  - `WineRunner.run(..., inheritIO: true)` for anything long-running or noisy (it hands the child the
    parent's stdio, so no pipe can fill), or
  - a `readabilityHandler` on **both** pipes so they drain concurrently, the way
    `CellarApp/CellarRunner.swift` streams the CLI's output.
  If you ever do need both captured *and* volume-safe, drain both handlers into buffers and only then
  `waitUntilExit()`.
- **Never `waitUntilExit()` before draining.** Same deadlock, more obvious.
- **Clear a `readabilityHandler` (set it to `nil`) once you see EOF** — an empty `availableData` —
  or the handle keeps firing and the process object stays alive.
- **Don't wrap Wine in `/usr/bin/arch -x86_64`.** SIP strips `DYLD_*` from system binaries and the
  runner's dylibs stop resolving. Run the x86_64-only Mach-O directly; Rosetta picks it up. See
  [`wine-and-runners.md`](wine-and-runners.md).

## SwiftUI + AppKit gotchas (load-bearing — do not regress)

`CellarApp` is a hand-rolled `NSApplication` hosting SwiftUI in an `NSHostingView` (a SwiftPM
executable can't use a `@main` App scene). That host has sharp edges we've already hit:

- **No `.animation(value:)` / `.transition` on the detail pane, and no `NavigationSplitView`.** Both
  trigger a **fatal AttributeGraph precondition cycle** (Abort trap 6) on launch under
  `NSHostingView`. Use **`HSplitView`**. Only *local* animation is safe (e.g. a row's hover state).
- **No SwiftUI `.sheet` / `.popover` in the hosted view tree.** A `.sheet(isPresented:)` triggers the
  **same AttributeGraph crash on launch** (it animates via `NSAnimationContext`, re-entering the main
  window's view graph). Present auxiliary UI (e.g. Settings) as a **separate `NSWindow`** hosting its
  own `NSHostingView` — a top-level window is its own graph, so it's safe. Bridge the button/menu →
  window with the `.cellarOpenSettings` notification; the window's view takes an `onClose` callback
  (there's no `dismiss` environment for a plain `NSWindow`).
- **The menu bar is built by hand** in `main.swift` — AppKit installs no default menu for a
  hand-rolled app. Keep the App menu (About, Settings… ⌘,, Quit ⌘Q), the **Edit menu**
  (cut/copy/paste/select-all — text fields need it), and the Window menu. If you add a window-level
  command, add its menu item too.
- **AppKit menu ↔ SwiftUI state** is bridged with a `Notification` (e.g. `.cellarOpenSettings`),
  because the menu lives in the `NSApplicationDelegate` and the state in a SwiftUI view. Reuse that
  seam rather than reaching across.
- **Present sheets you gate with `@State`.** A `showX = true` flag does nothing without a matching
  `.sheet(isPresented:)`.
- **UI mutation is main-thread only.** A subprocess `readabilityHandler` fires on a background queue,
  so hop (`await MainActor.run` / `DispatchQueue.main.async`) before touching `@State`. The crash
  this avoids is intermittent, which makes it worse than a deterministic one.

## Concurrency

Swift 5 language mode means the compiler is *not* checking you. That is a reason for discipline, not
a licence:

- Keep CellarKit's public types **value types with no shared mutable state** — they are then
  `Sendable` by construction, and the eventual Swift 6 migration is mechanical.
- Anything that touches `NSHostingView`, `NSWindow` or SwiftUI state is **`@MainActor` in practice**.
  Annotate it, even in v5 mode, so the intent survives the migration.
- If you *do* introduce `async`, don't half-migrate a call chain — a synchronous `Shell.run` called
  from an async context still blocks that thread.

## Testing

**There is no test target in `Package.swift` today.** `swift run cellar selftest` is a smoke test
*inside the CLI* — useful, and part of the verification ladder, but it is not a test suite: `swift
test` runs nothing, so nothing is covered in CI beyond "it built and the smoke test exited 0".

When you add tests (and new pure logic should come with them):

- **Use Swift Testing, not XCTest.** It ships with the Swift 6 toolchain — `import Testing` in a
  `.testTarget`, no package dependency. It is the 2026 default for new tests; XCTest remains only for
  UI and performance tests, which this repo has none of.
- `#expect(...)` for assertions, `#require(...)` when the test cannot continue on failure — two
  macros instead of XCTest's forty `XCTAssert*` variants.
- **Tests run in parallel by default.** Anything touching `~/Library/Application Support/Cellar`,
  `WINEPREFIX`, or the real filesystem must be given its own temporary directory, or parallel runs
  will collide. Prefer pure functions that need no filesystem at all.
- **Start with the pure codecs** — `BinaryVDF`, `CRC32`, `SteamShortcut`, and the profile/bottle
  scanners in `Profile.swift`/`Prefix.swift`. They are total functions over bytes and strings, they
  already have known-good vectors in `selftest`, and the scanners have real edge cases worth pinning
  (see [`profiles.md`](profiles.md)).
- Don't write tests that drive Wine or the network. Those are the *behaviour* rung of the ladder and
  belong in a launched build, not in `swift test`.

## Style

- Match the file you're in: small types, descriptive names, comments only where intent isn't obvious.
- Follow the Swift API Design Guidelines: name methods for their side effects (`setUp()`, not
  `doSetup()`), keep argument labels reading as a phrase, and don't abbreviate.
- Prefer value types and pure functions in CellarKit; keep side effects (shell, filesystem) behind
  named helpers (`Shell`, `Paths`, …) that already exist.
- Public API on CellarKit types is a contract the CLI and app both use — widen it deliberately.
- Every `CellarError` on a player-facing path ends with the command or button that fixes it — that is
  a UX rule, enforced in [`ux.md`](ux.md).

## Verify (before claiming done)

1. `env -u DEVELOPER_DIR -u SDKROOT swift build -c release` clean.
2. `swift run cellar selftest` passes (and `swift test`, once a test target exists).
3. Behaviour: run the CLI command, or `sh Scripts/install-app.sh` and launch the app and exercise the
   path. GUI changes are **not** verified by reading the diff.

Related: [`ux.md`](ux.md) · [`wine-and-runners.md`](wine-and-runners.md) · [`profiles.md`](profiles.md)
· [`web.md`](web.md) · [`shell-and-packaging.md`](shell-and-packaging.md) ·
[`../agents/verifier.md`](../agents/verifier.md)
