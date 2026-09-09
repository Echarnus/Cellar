---
name: cellar-swift
description: Best practices for Swift, SwiftUI and AppKit in the Cellar repo. Use when editing anything under Sources/** — CellarKit, the cellar CLI, or the CellarApp SwiftUI app. Covers the SDK-unset build command, keeping logic in CellarKit, the subprocess pipe-deadlock rules for a project that is mostly a process driver, testing with Swift Testing (there is no test target yet), and the load-bearing SwiftUI/NSHostingView gotchas (AttributeGraph crash, HSplitView, the hand-built menu bar).
---

# Cellar — Swift / SwiftUI / AppKit

The full guide is [`skills/swift.md`](../../../skills/swift.md); read it. Key rules:

- **Build:** `env -u DEVELOPER_DIR -u SDKROOT swift build -c release` (a Nix/devenv shell breaks a
  plain build). Swift 5 language mode — don't add async/actor machinery without cause.
- **All logic in `CellarKit`;** the CLI and app are thin. The app drives the `cellar` CLI as a
  subprocess for actions — don't reimplement an action in a view. **CellarKit never `print`s** —
  terminal output is the CLI's job, and it is UI.
- **Subprocesses (this project is mostly a process driver).** `Shell.run` drains stdout to EOF *then*
  stderr — safe only because its outputs are tiny, and it says so. A chatty child (Wine, above all)
  can fill the stderr pipe buffer while the parent blocks on stdout and **deadlock both sides**. Use
  `WineRunner.run(inheritIO: true)` or `readabilityHandler`s draining **both** pipes concurrently, as
  `CellarRunner.swift` does. Never `waitUntilExit()` before draining; clear a handler at EOF; hop to
  the main actor before touching `@State` from one.
- **Testing:** there is **no test target** — `swift test` runs nothing, and `cellar selftest` is a
  smoke test, not a suite. New pure logic should come with tests: **Swift Testing** (`import
  Testing`, `#expect`/`#require`), which ships with the toolchain. Tests run in parallel, so anything
  touching the real filesystem needs its own temp dir. Start with the pure codecs (`BinaryVDF`,
  `CRC32`, `SteamShortcut`) and the profile/bottle scanners.
- **SwiftUI under `NSHostingView` (no `@main` scene) — do not regress:** no `NavigationSplitView`,
  no `.animation`/`.transition` on the detail pane, and **no SwiftUI `.sheet`/`.popover`** — all
  trigger a fatal AttributeGraph cycle on launch. Use `HSplitView`; present auxiliary UI (Settings)
  as a separate `NSWindow`, not a sheet. The menu bar is hand-built in `main.swift` (keep
  App/Edit/Window, ⌘Q); bridge menu/button → window via the `.cellarOpenSettings` `Notification`.
- **Verify** (not by reading the diff): build clean → `swift run cellar selftest` → for GUI, `sh
  Scripts/install-app.sh` and launch and exercise the path.

Before reporting done, run the **cellar-verifier** agent.
