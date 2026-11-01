## What and why

<!-- What this changes, in a sentence or two, and why. -->

Closes #

## How it was verified

<!-- The same bar for every author, AI agents included: tick only what you actually ran, and paste
the result that proves it (the test count, the command's output, a screenshot). An unticked rung
is fine if you say who has to run it. The PR checklist check fails until at least one is ticked. -->

- [ ] Builds (`swift build -c release`)
- [ ] Tests pass (`sh app/Scripts/test.sh`), and coverage holds (`sh app/Scripts/test.sh --coverage`)
- [ ] Self-test passes (`swift run cellar selftest`)
- [ ] Wine tiers (`sh app/Scripts/test.sh --integration`) — for runners, prefixes, launching
- [ ] Real game (`sh app/Scripts/test.sh --steam`) — for depots, ownership, store credentials
- [ ] Ran it: the CLI command or the installed app — for anything a player sees

## Delivery checklist

<!-- docs/DELIVERY-CHECKLIST.md: one yes/no line per thing that once reached Kenneth broken. Tick a
line only with evidence above (a `cellar verify` report, test output, a screenshot). A line that
cannot apply stays unticked and says why after "n/a:". PR checklist fails a PR that changes app code,
a profile or the shim while any box is unticked without an n/a: reason. -->

- [ ] A1 proven: "done" comes with evidence Claude produced, never "please check"
- [ ] A2 his-bar: every done-criterion Kenneth stated for this is met, no workaround that drops one
- [ ] A3 prs-green: every PR for this is green, conflict-free and merged by its author
- [ ] A4 release-scope: nothing ships in a release until what was named for it passes
- [ ] A5 his-hands-only: Kenneth is asked only for sign-ins and macOS prompts
- [ ] G1 signed-in: Steam signed in, no sign-in window (`cellar verify`)
- [ ] G2 steam-online: Steam online by its connection log (`cellar verify`)
- [ ] G3 game-online: the game's own process reaches its servers, no TLS errors (`cellar verify`)
- [ ] G4 stays-up: several cold launches stay up, no crash reporter (`cellar verify`)
- [ ] G5 dlc: all owned DLC installed and seen by Steam (`cellar verify`)
- [ ] G6 dock: only Cellar and the game in the Dock, by its proper name, no Steam or wine (`cellar verify`)
- [ ] G7 clean-exit: no Wine left after quitting, Play back within 30 s (`cellar verify`)
- [ ] G8 settings-match: bottle settings match the profile and the Mac's language (`cellar verify`)
- [ ] G9 real-install-untouched: real runners and bottles unchanged by tests (`test.sh`, `cellar verify`)
- [ ] P1 no-terminal: no player step needs Terminal; Cellar repairs itself
- [ ] P2 plain-words: no bottle, runner, Wine, prefix, D3DMetal, log or profile on player screens
- [ ] P3 own-state: each game's page shows only its own state
- [ ] P4 art-keeps-shape: covers and banners keep their proportions
- [ ] P5 responsive: the app answers clicks during and after a download

## Tests

<!-- Which tests this adds or changes, and what each would catch if the change broke. A change to
Swift under app/src/ or app/Packages/*/Sources/ must touch a test — or replace this comment with one line saying why it can't:

No tests needed: <the reason, about this change>
-->

## Notes for the release

<!-- Anything a player should read in the release notes. Label the linked issue so it lands in
the right section; label this PR `skip-changelog` if it should not appear at all. -->
