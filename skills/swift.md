# Skill: Swift, SwiftUI & AppKit in Cellar

Best practices for `Sources/**`. Portable guide; Claude's auto-discovered copy is
`.claude/skills/cellar-swift/SKILL.md`. Read [`../AGENTS.md`](../AGENTS.md) first.

## Build

Always release-build with the SDK vars unset, or a Nix/devenv shell links the wrong SDK:

```sh
env -u DEVELOPER_DIR -u SDKROOT swift build -c release
```

The package is Swift-tools 6.0 but compiles in **Swift 5 language mode** (`swiftLanguageModes:
[.v5]`) — a synchronous CLI doesn't need strict-concurrency overhead yet. Don't add `async`/actor
machinery unless a target genuinely needs it.

## Architecture rules

- **All logic lives in `CellarKit`.** The CLI (`Sources/cellar`) and the app (`Sources/CellarApp`)
  are thin. Never duplicate engine logic in a command or a view — add it to CellarKit and call it.
- **The GUI drives the CLI as a subprocess** for side-effecting actions (setup, install, launch), so
  it inherits every tested path (silent Steam, the launch auto-retry, close-on-exit). Read-only state
  comes from `Game.summaries()`. Don't reimplement an action inside the app.
- **CLI:** one file per command group under `Commands/`, ArgumentParser, small `struct` commands.

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

## Style

- Match the file you're in: small types, descriptive names, comments only where intent isn't obvious.
- Prefer value types and pure functions in CellarKit; keep side effects (shell, filesystem) behind
  named helpers (`Shell`, `Paths`, …) that already exist.
- Public API on CellarKit types is a contract the CLI and app both use — widen it deliberately.

## Verify (before claiming done)

1. `env -u DEVELOPER_DIR -u SDKROOT swift build -c release` clean.
2. `swift run cellar selftest` passes.
3. Behaviour: run the CLI command, or `sh Scripts/install-app.sh` and launch the app and exercise the
   path. GUI changes are **not** verified by reading the diff.

Related: [`web.md`](web.md) · [`shell-and-packaging.md`](shell-and-packaging.md) ·
[`../agents/verifier.md`](../agents/verifier.md)
