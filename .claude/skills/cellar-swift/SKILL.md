---
name: cellar-swift
description: Best practices for Swift, SwiftUI and AppKit in the Cellar repo. Use when editing anything under Sources/** — CellarKit, the cellar CLI, or the CellarApp SwiftUI app. Covers the SDK-unset build command, keeping logic in CellarKit, and the load-bearing SwiftUI/NSHostingView gotchas (AttributeGraph crash, HSplitView, the hand-built menu bar).
---

# Cellar — Swift / SwiftUI / AppKit

The full guide is [`skills/swift.md`](../../../skills/swift.md); read it. Key rules:

- **Build:** `env -u DEVELOPER_DIR -u SDKROOT swift build -c release` (a Nix/devenv shell breaks a
  plain build). Swift 5 language mode — don't add async/actor machinery without cause.
- **All logic in `CellarKit`;** the CLI and app are thin. The app drives the `cellar` CLI as a
  subprocess for actions — don't reimplement an action in a view.
- **SwiftUI under `NSHostingView` (no `@main` scene) — do not regress:** no `NavigationSplitView` and
  no `.animation`/`.transition` on the detail pane (fatal AttributeGraph cycle) — use `HSplitView`;
  the menu bar is hand-built in `main.swift` (keep App/Edit/Window, ⌘Q); bridge menu→view state via
  a `Notification`; a `@State`-gated sheet needs a matching `.sheet(isPresented:)`.
- **Verify** (not by reading the diff): build clean → `swift run cellar selftest` → for GUI, `sh
  Scripts/install-app.sh` and launch and exercise the path.

Before reporting done, run the **cellar-verifier** agent.
