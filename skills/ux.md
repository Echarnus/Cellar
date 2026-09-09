# Skill: UX & UI in Cellar

**The interface is the product.** Cellar's job is to make a Windows game start on a Mac, and the
only way anyone experiences that job being done is the app in front of them. A change that works but
looks or reads like a developer tool has not landed. Hold every user-visible change to the standard
Apple holds its own apps to.

Portable guide; Claude's auto-discovered copy is `.claude/skills/cellar-ux/SKILL.md`. Read
[`../AGENTS.md`](../AGENTS.md) first, and [`swift.md`](swift.md) for the SwiftUI mechanics — including
the crashes that constrain what you may build.

---

## The bar

Ask these before calling anything done. Any "no" is a defect, not a polish item.

1. **Can a player who has never seen Cellar tell what to do next?** There is exactly one obvious
   next action per screen, it is the biggest control, and a plain sentence under it says what will
   happen.
2. **Is every state accounted for?** Empty, loading, first-run, partial, error, and busy. A screen
   that only looks right when everything is installed is unfinished.
3. **Does it tell the truth?** Never show a ✓ for something Cellar cannot actually check, and never
   claim a step is automatic when the player will have to click something. See *Honesty* below.
4. **Does it read like a person wrote it?** Sentence case, no jargon the player did not choose to
   learn, no `WINEPREFIX` in front of someone who wants to play Diablo.
5. **Does it work for someone who can't see the colour?** Every meaning carried by colour is also
   carried by a mark and a word.
6. **Is it still right in the other appearance?** Light and dark, and at the window's minimum size.

## Honesty is a UX rule, not just an ethical one

Cellar drives other people's software. Some of what it would like to know is not knowable, and the
interface must say so rather than guess:

- Steam writes `loginusers.vdf`, so "Signed in as kenneth" is a fact and gets a ✓.
- Battle.net exposes nothing equivalent. So Cellar does **not** show a sign-in step for it, does not
  show a ✗ next to "account", and folds signing in into "Open Battle.net" — the one screen where the
  player can actually resolve it. `cellar battlenet status` prints a `·`, never a ✗.
- Battle.net's installer cannot run silently. Setup therefore *warns first* ("its window will open
  and needs a few clicks") instead of appearing to hang and being killed by an impatient player.

The rule: **a control Cellar cannot honour must not exist, and a pause the player will notice must
be announced before it happens.** Encode the difference in `GameStore.descriptor` so every surface
inherits it, rather than special-casing a store in a view.

## Telling the stores apart

A game's store decides what every button does next, so it is primary information, never a footnote.
It is carried by **three signals, always together** — see `Sources/CellarUI/StoreStyle.swift`:

| Signal | Where |
|---|---|
| **Position** | The library is grouped into store sections, in a fixed order. A game's neighbours already tell you. |
| **Mark** | The store's real logo, drawn as vectors in `StoreMark.swift`, on the cover badge, section heading, filter chip and detail lockup. |
| **Word** | The store's name, spelled out, beside the mark and in every accessibility label. |

Notes that are easy to get wrong:

- **Colour cannot carry this alone.** Steam and Battle.net are both blue. The tints in
  `StoreDescriptor.accentHex` differentiate *tone*, but the mark and the word do the work.
- **Store marks are drawn, never bundled.** `AGENTS.md` forbids redistributing anyone's proprietary
  assets, and a logo PNG in `Resources/` would break it. Vector marks keep the repo asset-free, stay
  crisp at any size, and work offline. Use is nominative — labelling where a game came from, not
  claiming endorsement (`NOTICE`).
- **Trace the mark, never draw it from memory — and never invent one.** Drawn-in-code is a
  distribution rule, not a licence to approximate: the player knows these logos, and a wrong one
  reads as a fake. Every mark so far has been wrong at least once from being sketched rather than
  looked at — Steam's wheels swapped, Blizzard's orb drawn as a *spiral* when it is three crossing
  orbits, and GOG given an invented purple "G" disc when its mark is the white `gog`/`com` tile. An
  invented mark is the worst of the three: it teaches the player something that matches nothing they
  will ever see on the store. Put the real mark on screen next to the drawing, zoom in, and copy the
  geometry — the numbers in `StoreMark.swift` are measurements, and the comments say what they were
  measured from.
- **A mark is not obliged to be a disc.** GOG's is a light rounded tile among saturated circles,
  which is a *stronger* signal, not a lapse — but anything drawing around a mark must ask
  `StoreMark.outline(of:size:)` rather than assuming a circle.
- **Judge a mark at the size *and scale* the player gets, not the one you drew it at.** Authentic and
  unreadable is not an improvement on wrong. The app's commonest marks are a **12pt** filter chip and
  a **13pt** section heading — 24 device pixels on a 2× screen — so detail finer than a pixel becomes
  grey static however correct the geometry is. GOG's mark therefore drops to a single glyph below
  20pt. Zoom a snapshot to *inspect* a mark, never to *approve* one: `markSurvivesAtDeviceScale`
  renders at 2× for exactly this reason, and it exists because an 8× render passed a mark the app
  showed as mush.
- **Never leave a blank cover.** Steam publishes key art per AppID; Battle.net publishes none a
  launcher may hotlink. `GeneratedCover` composes a deterministic gradient and monogram instead —
  deterministic because a cover that changed colour between launches would read as a bug.

## Copy

- **Say what happens, in one sentence.** "Battle.net opens. Sign in if you haven't, then install the
  game from there." Not "Launch external client."
- **Name the thing the player will see.** If a Blizzard window is about to appear, say "Battle.net",
  not "the store client".
- **Errors point at the fix.** Every thrown `CellarError` in a player-facing path ends with the
  command or the button that resolves it.
- **Sentence case** for buttons, labels and notices. Store names keep their own capitalisation.
- Sizes and counts are human: "a few minutes", "~1.4 GB", "6 games · 2 stores".

## Accessibility

- Icon-only controls need `.accessibilityLabel` **and** `.help` (the tooltip).
- Composite rows use `.accessibilityElement(children: .combine)` with a label that reads the whole
  row: name, store, state.
- Decorative art is `.accessibilityHidden(true)` — a cover behind a title is noise to VoiceOver.
- Don't lower contrast for style. Secondary text stays `.secondary`, not a hand-rolled grey.

## Craft details that separate this from a tool

- **Continuous corner radii** (`style: .continuous`) on cards and covers; radius scales with the
  element, it is not a magic 8 everywhere.
- **Hover is local.** A row may animate its own highlight; the detail pane may not animate at all
  (it crashes — see [`swift.md`](swift.md)).
- **Remember what the player did**: the selected game, the filters. Reopening where you left off is
  the least a library can do.
- **Depth is subtle.** Soft shadow and a hairline `.white.opacity(0.10)` border on art; no heavy
  drop shadows, no gratuitous blur.

## Verify (before claiming done)

Compiling proves nothing about an interface.

1. `sh Scripts/install-app.sh` (or `Scripts/package.sh` and run `dist/Cellar.app`).
2. **Launch it and look at it.** Screenshot the changed screen.
3. Check the states you changed — including the empty and not-installed ones — and both appearances.
4. Re-read every new sentence aloud. If it sounds like a log line, rewrite it.

Related: [`swift.md`](swift.md) · [`web.md`](web.md) · [`../agents/verifier.md`](../agents/verifier.md)
