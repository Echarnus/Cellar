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
6. **Is it still right in the other appearance?** Light and dark, at the window's minimum size, and
   at a larger system text size.

## Honesty is a UX rule, not just an ethical one

Cellar drives other people's software. Some of what it would like to know is not knowable, and the
interface must say so rather than guess:

- Steam writes `loginusers.vdf`, so "Signed in as kenneth" is a fact and gets a ✓.
- Battle.net exposes nothing equivalent — no signed-in state, no entitlements. So Cellar never shows
  a ✓ or a ✗ for it (`cellar battlenet status` prints a `·`), and the sign-in itself still happens
  inside Blizzard's client, where it always did. What Cellar *does* ask, once, in Accounts, is
  whether the player has an account there at all — because the library will not list a store nobody
  has connected, and asking is the only way this one can ever be known. The row says "Added by you",
  never "Signed in": the words carry who did the claiming.
- Battle.net's installer cannot run silently. Setup therefore *warns first* ("its window will open
  and needs a few clicks") instead of appearing to hang and being killed by an impatient player.
- macOS's folder prompts are **asked for on first launch, not stumbled into**. Windows games save
  into Documents/Desktop/Downloads, so the prompts are unavoidable — but *when* they appear is
  Cellar's to choose, and "mid-install, unexplained" is the one wrong answer. A folder the player
  turns down is honoured and said so (saves stay in the bottle), never quietly broken. And nothing
  shows a ✓ for a folder that was never asked about: that row reads "Not asked yet".

The rule: **a control Cellar cannot honour must not exist, and a pause the player will notice must
be announced before it happens.** Encode the difference in `GameStore.descriptor` so every surface
inherits it, rather than special-casing a store in a view.

## Telling the stores apart

A game's store decides what every button does next, so it is primary information, never a footnote.
It is carried by **three signals, always together** — see `Sources/CellarUI/StoreStyle.swift`:

| Signal | Where |
|---|---|
| **Position** | The library is grouped into store sections, in a fixed order. A game's neighbours already tell you. |
| **Mark** | The store's real logo — its own icon from the copy installed on this machine (`StoreIcon.swift`), else the vector Cellar draws (`StoreMark.swift`) — on the cover badge, section heading, filter chip and detail lockup. |
| **Word** | The store's name, spelled out, beside the mark and in every accessibility label. |

Notes that are easy to get wrong:

- **Colour cannot carry this alone.** Steam and Battle.net are both blue. The tints in
  `StoreDescriptor.accentHex` differentiate *tone*, but the mark and the word do the work.
- **Store marks are never bundled — Cellar points at the install instead.** `AGENTS.md` forbids
  redistributing anyone's proprietary assets, and every store's own brand terms forbid shipping its
  logo besides, so a logo PNG in `Resources/` is out twice over. Cellar shows the **real icon from
  the store already installed on this machine** (`StoreIcon.swift` — the Mac app's `.icns`, the icon
  Wine extracted from the Windows client, or a loose `.ico`), and falls back to a vector it draws
  itself when there is nothing to point at. The drawn mark is therefore not a placeholder: for a
  store the player hasn't installed, it is what ships. Use is nominative — labelling where a game
  came from, not claiming endorsement (`NOTICE`).
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

Apple's [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/accessibility)
are the external standard here; this is what it means for Cellar specifically.

- Icon-only controls need `.accessibilityLabel` **and** `.help` (the tooltip).
- Composite rows use `.accessibilityElement(children: .combine)` with a label that reads the whole
  row: name, store, state.
- Decorative art is `.accessibilityHidden(true)` — a cover behind a title is noise to VoiceOver.
- Don't lower contrast for style. Secondary text stays `.secondary`, not a hand-rolled grey. The
  measurable bar is WCAG AA: **≥ 4.5:1 for body text, ≥ 3:1 for large text and UI components.**
- **Use semantic text styles** (`.body`, `.headline`, `.caption`) rather than
  `.font(.system(size:))`. Semantic styles follow the user's system text size; a hard-coded point
  size does not, and a player who has turned text up gets a layout that silently ignores them. The
  app is mostly right on this already — a handful of fixed sizes remain, so don't add more.
- **The keyboard must reach everything.** Tab order follows the visual layout, focus is always
  visible, and anything with a menu item keeps its ⌘-shortcut. The menu bar is hand-built
  ([`swift.md`](swift.md)), so a new window-level command needs its menu entry added by hand or it
  becomes mouse-only.
- Respect reduced motion. Given that the detail pane cannot animate at all under `NSHostingView`,
  this mostly means: don't add motion to work around that constraint. Where motion does exist, read
  `@Environment(\.accessibilityReduceMotion)` and drop it: the sidebar's hover fade, the cover
  art's fade-in, and the indeterminate progress sweep (which holds still mid-track instead).
- **Increase Contrast** (`@Environment(\.colorSchemeContrast) == .increased`) gets stronger
  fills wherever a state is carried by a faint tint: the sidebar's selection and hover, the progress
  track. Any new `opacity(0.0x)` fill that means something needs the same.
- **Store marks and covers are hidden from VoiceOver on purpose.** `StoreMark` and `GameCover`
  hide themselves, because the rule is that a mark or a cover never appears without the store's or
  the game's name in words beside it — reading both says everything twice. If you ever place a mark
  alone, give that placement its own `.accessibilityLabel`.
- **What still needs a Mac:** a pass with Accessibility Inspector's audit and a walk through the
  library, a game page and a launch with VoiceOver on (⌘F5). Nobody has done that pass yet; record
  what it finds here.

## Localization — English and Dutch

**The app is translated into Dutch — its screens, alerts and menu bar; the CLI and the copy CellarKit
computes are still English.** The tables live in `Resources/Localization/<lang>.lproj/Localizable.strings`,
the install scripts copy them into the bundle, and SwiftUI looks every `Text("…")`, `Button("…")`,
`Label("…", …)`, `Toggle`, `Section`, `Picker`, `Link`, `LabeledContent`, `.help` and
`.accessibility{Label,Value,Hint}` literal up by its English text. Anything that is not a SwiftUI
view — an `NSAlert`, a menu item — wraps its literal in `String(localized: "…")`.

- **A new literal in the app needs a Dutch entry.** `LocalizationTests` fails until it has one, and
  fails again when a reworded literal leaves its old key behind — the key *is* the English text.
- **Write whole sentences with the variable interpolated in one piece.** `Text("Connected: \(names)")`
  becomes the key `Connected: %@` (an `Int` becomes `%lld`); `Text("Needs " + store)` is a `String`, which SwiftUI shows verbatim
  and never translates — and word order differs per language anyway. Never interpolate an English word
  (`"\(n) \(n == 1 ? "game" : "games")"`): write both sentences as literals and pick one.
- **A long caption stays one literal.** Use a multi-line `"""` literal with `\` line continuations,
  not `"…" + "…"`: concatenation turns it into a `String` and it silently stays English.
- **Text held in a `String` variable is not looked up.** A custom view that takes `title: String`
  shows it verbatim, and so does copy computed in CellarKit (readiness lines, hints, errors): those
  are the next step, and need the parameter to become a `LocalizedStringKey`, or the copy to come
  from `String(localized:)` with a bundle CellarKit can find.
- **Dutch runs about a third longer than English.** Check the minimum window width with the Mac set
  to Nederlands (System Settings → General → Language & Region, or per app under Applications).

To add a language: copy `nl.lproj` to `<code>.lproj`, translate the values (never the keys), and add
the code to `CFBundleLocalizations` in both `Scripts/install-app.sh` and `Scripts/package.sh`.

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

Related: [`swift.md`](swift.md) · [`wine-and-runners.md`](wine-and-runners.md) ·
[`profiles.md`](profiles.md) · [`web.md`](web.md) · [`../agents/verifier.md`](../agents/verifier.md)
