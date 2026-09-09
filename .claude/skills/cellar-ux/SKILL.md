---
name: cellar-ux
description: The UX/UI bar for Cellar — non-negotiable, because the interface is the product. Use when changing anything a player sees: the SwiftUI app, CLI output wording, error messages, notices, or the store presentation. Covers the Apple-grade checklist, honesty as a UX rule (never show a state Cellar cannot verify), how the stores are told apart (position + mark + word, marks drawn not bundled), copy style, accessibility, and the launch-and-look verification.
---

# Cellar — UX / UI

The full guide is [`skills/ux.md`](../../../skills/ux.md); read it before changing anything a player
sees. **The interface is the product** — a change that works but reads like a developer tool has not
landed. Key rules:

- **The bar:** one obvious next action per screen with a plain sentence under it; every state
  designed (empty, loading, first-run, busy, error); light *and* dark; minimum window size.
- **Honesty is a UX rule.** Never show a ✓ for something Cellar cannot check, never imply a step is
  automatic when the player must click. Steam publishes who is signed in; Battle.net does not — so
  Battle.net has no sign-in step (Accounts only asks you to *add* it, and says who is claiming what)
  and its installer is announced as needing clicks. Encode the difference in `GameStore.descriptor`,
  never as a special case in a view.
- **Stores are told apart by three signals together:** position (grouped sections), mark (the store's
  real logo, drawn as vectors in `StoreMark.swift`), and word (its name, including in a11y labels).
  Colour never carries it alone — Steam and Battle.net are both blue.
- **Marks are never bundled — grafted first, drawn second, and the drawing is traced, never
  remembered or invented.** Shipping Valve's or Blizzard's artwork breaks a hard rule in `AGENTS.md`
  and those companies' own brand terms. Cellar shows the real icon from the store's install on this
  machine (`StoreIcon.swift`) and draws its own vector when there is none (`StoreMark.swift`) — that
  drawn fallback is what ships for an uninstalled store, so it has to be right. Drawing one from
  memory ships a logo the player can see is wrong: put the real mark on screen, zoom in, copy the
  geometry. Not every mark is a disc — ask `StoreMark.outline(of:size:)` before ringing one. Never
  leave a blank cover either: `GeneratedCover` draws a deterministic one.
- **Then judge it at the size *and scale* it ships at.** A 12pt chip is 24 device pixels; detail finer
  than a pixel is static, however authentic. Zoom to inspect, never to approve — `Scripts/test.sh`'s
  `markSurvivesAtDeviceScale` renders at 2× because an 8× render once passed a mark the app showed as
  mush.
- **Copy:** sentence case, say what will happen in one sentence, name the window the player will see,
  and end every player-facing error with the command or button that fixes it.
- **Accessibility** (Apple's HIG is the external standard): icon-only controls get
  `.accessibilityLabel` + `.help`; rows combine into one label that reads name, store and state;
  decorative art is hidden from VoiceOver. Contrast **≥ 4.5:1** body / **≥ 3:1** large text and UI.
  Prefer **semantic text styles** (`.body`, `.headline`) over `.font(.system(size:))` so the app
  follows the system text size. Everything must be reachable by keyboard — and a new window-level
  command needs its menu item added by hand, or it is mouse-only.
- **Not localized, deliberately — don't make it worse.** Every string is a hard-coded English
  literal; there is no String Catalog. So never build a sentence from concatenated fragments (it
  cannot be translated and reads badly to VoiceOver) — interpolate into a whole sentence.
- **Verify by launching, not by compiling.** `Scripts/install-app.sh` (or `package.sh` + run
  `dist/Cellar.app`), then look at the changed screen and screenshot it.

Mechanics and the crashes that constrain the UI live in
[`cellar-swift`](../cellar-swift/SKILL.md) / [`skills/swift.md`](../../../skills/swift.md).
