# Cellar design principles

**Mandatory for every change a player can see**: the app, the CLI's wording, error text, the
installer and the site. This page holds the principles and Kenneth's standing product rules.
[`skills/ux.md`](../skills/ux.md) is the working guide (copy, accessibility, localization, store
marks), and it follows from this page. A change that breaks a rule here is not done, however well
it works.

Cellar's bar is **Apple's Human Interface Guidelines** (developer.apple.com/design/human-interface-guidelines):
a Cellar window should be hard to tell apart from one Apple made. Where this page and the HIG
disagree, this page wins, because it records a decision Kenneth made for Cellar.

## 1. Who it is for

**Everyone, not just people who know Wine.** Cellar is a simple app that gives clear information
about each game and is easy to use for all players. It can still be troubleshot when needed, but
that happens one level down and is never in the way.

- One obvious next action per screen: the game page has one big button (Play, Install, Set up)
  and a sentence saying what it will do.
- A game's page shows only facts about that game: its state, whether it is tested, what it needs.
  It does not show the store's name or the account under the title. The sidebar's store section
  already says the store, and the account button at its foot says who is signed in (#266).
- Troubleshooting lives in the "…" menu's **Troubleshooting** submenu and in **Technical
  Details**. It never sits on the main page. The diagnostics report is the single way out for a
  bug report.
- No raw logs anywhere in the window. Logs are written to disk, exported by "Save Diagnostics
  Report", and found with "Show Logs in Finder" (#266).

## 2. Plain words: never the plumbing

- A player never reads **wine, bottle, prefix, runner, D3DMetal, DXVK, profile, manifest, depot or
  log** on a player screen (delivery checklist **P2**). Technical Details is the one exception,
  because it exists to show those things.
- **"wine" never appears as the name of anything a player can see**, including the Dock tooltip,
  ⌘-Tab, the menu bar and Force Quit. Every process Cellar starts for a game shows the game's
  name: the game itself, the store's stub (`PlayGTAV.exe`), and a publisher launcher (the Rockstar
  Games Launcher). The Dock shim does this (`DockShim`, `PublisherLauncher.windowedExecutables`).
  A store client the player didn't open stays out of the Dock altogether (#201, #220, #266).
- **Never a Terminal command for a player.** Not in an error, not in a dialog, not in release
  notes. Cellar repairs itself instead (**P1**). The CLI may print commands, because its user
  chose a terminal.
- Dialogs say what a player is deciding. The uninstall dialog says how much space it frees and
  that the game can be downloaded again, and nothing about manifests or runners (#266).

## 3. Honest state

- **Never a ✓ for something Cellar can't check.** Never imply a step the player won't have to do
  themselves (Rockstar's and Battle.net's sign-ins are the player's, said up front).
- **Loading is a state.** Until Cellar knows something, it says it is loading. It never shows a
  guess: no "Sign in" to a signed-in player while the library loads (#266). Use a neutral
  placeholder the shape of the content, or a small spinner with a sentence.
- Every state is designed: empty, loading, first run, busy, error, and the one where the network
  is down.
- **No hiding a problem as a fix.** Hiding DLC that doesn't load, or a feature that fails, is not a
  fix (Planet Coaster 2: all DLC, the Workshop, and no crash reporter, or it isn't done).
- The library shows **the games you own**, never the catalogue. Ownership has three answers:
  owned, not owned, and can't tell.

## 4. Stores

- **Every game comes through a store. There is no other way in.** There is no "add a game
  manually" option and no "no store" option, in the app, the CLI or the site.
- **Steam only for the first release.** Battle.net and GOG are hidden behind
  `StoreAvailability.offered` (and `OFFERED` on the site), not deleted. Re-enable a store in both
  places.
- Sign-in is account-level, done once in Settings, never per game. Games reuse it with no second
  prompt and stay online.
- The Steam client in a bottle is plumbing. It never shows in the Dock, and the game's menu
  doesn't offer to open it or to install through it (#266).
- Stores are told apart by **position, mark and word together**, never by colour alone. Store
  marks are never bundled logo files (see `AGENTS.md` → trademark-safe).

## 5. Mac conventions (HIG)

- **Native controls first**: a segmented control, `NSAlert`, menus and `Form` in Settings. A
  custom control has to earn its place. Segmented controls keep **equal-width segments**, so
  nothing shifts when the selection moves (`EqualSegmentedPicker`).
- **Every clickable thing answers hover.** Use `HoverButtonStyle` (`.hoverBordered`,
  `.hoverProminent`, `.hoverBorderless`, `.hoverLink`), which every window's root sets as
  `.hoverAutomatic`. Use `.hoverHighlight(.backdrop)` on menus and icon buttons. Disabled controls
  don't react.
- **Right-click works where a Mac user expects it.** A game in the sidebar has a context menu with
  its big action and Settings…, the way Steam's library does.
- **Title-style capitalization** for buttons, menu items and window titles ("Check for Updates",
  "Show Logs in Finder"). Use sentence case for labels, descriptions and alerts' informative text.
  An item that opens a window or asks something more ends in "…".
- Settings apply as they change: no Save or Done button. Window-level settings live in Settings
  (⌘,), and per-game overrides on the game's page. A setting a player wants for every game (Retina,
  MetalFX, frame rate) is offered in Settings as well as per game (#266).
- A destructive button is never the default: Return picks Cancel. Alerts show the subject's own
  icon (the game's cover when removing a game), not the app's.
- Light and dark, Increase Contrast, Reduce Motion, VoiceOver labels on every control, and the
  minimum window width are all checked, not assumed.
- Show the player themselves: their Steam profile picture in the account button, not a generic
  person.

## 6. Hands-off

Kenneth's rule, and the player's: **no manual steps.** No Terminal, no re-running jobs, no
copying files. If something can break, Cellar notices it and repairs it, and says so in one line.

## 7. How a change is checked against this page

1. Before writing the code: which of the rules above does the change touch?
2. The UI-facing wording is covered by a test (plain words, no commands, the right state). The
   look is covered by a CellarUI snapshot where it can be (`app/.build/ui-snapshots/`).
3. The installed app is launched and looked at in light and dark (rung 6 of the verification
   ladder). The PR's delivery checklist lines **P1–P5** are ticked with evidence.
4. A new correction from Kenneth becomes a new rule here and a line in
   [`DELIVERY-CHECKLIST.md`](DELIVERY-CHECKLIST.md), with a test where one can hold it
   ([`REGRESSIONS.md`](REGRESSIONS.md)).
