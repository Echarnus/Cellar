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
  Battle.net has no sign-in step and its installer is announced as needing clicks. Encode the
  difference in `GameStore.descriptor`, never as a special case in a view.
- **The library shows the player's own games, and says so honestly.** Nothing is listed until a store
  is connected, then only what that store confirms is owned. A store that *could* answer but hasn't
  been asked (Steam without a Web API key) hides its games and the screen says how to fix it; a store
  that can *never* answer (Battle.net) shows them and the screen says Cellar cannot check. The rule
  is `LibraryAccess.isVisible` in CellarKit — never a second copy in a view or command.
- **Stores are told apart by three signals together:** position (grouped sections), mark (the store's
  real logo, drawn as vectors in `StoreMark.swift`), and word (its name, including in a11y labels).
  Colour never carries it alone — Steam and Battle.net are both blue.
- **Marks are drawn, never bundled.** Shipping Valve's or Blizzard's artwork breaks a hard rule in
  `AGENTS.md`. Never leave a blank cover either: `GeneratedCover` draws a deterministic one.
- **Copy:** sentence case, say what will happen in one sentence, name the window the player will see,
  and end every player-facing error with the command or button that fixes it.
- **Accessibility:** icon-only controls get `.accessibilityLabel` + `.help`; rows combine into one
  label that reads name, store and state; decorative art is hidden from VoiceOver.
- **Verify by launching, not by compiling.** `Scripts/install-app.sh` (or `package.sh` + run
  `dist/Cellar.app`), then look at the changed screen and screenshot it.

Mechanics and the crashes that constrain the UI live in
[`cellar-swift`](../cellar-swift/SKILL.md) / [`skills/swift.md`](../../../skills/swift.md).
