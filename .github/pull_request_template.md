## What and why

<!-- What this changes, in a sentence or two, and why. -->

Closes #

## How it was verified

<!-- The same bar for every author, AI agents included: tick only what you actually ran, and paste
the result that proves it (the test count, the command's output, a screenshot). An unticked rung
is fine if you say who has to run it. The PR checklist check fails until at least one is ticked. -->

- [ ] Builds (`swift build -c release`)
- [ ] Tests pass (`sh Scripts/test.sh`), and coverage holds (`sh Scripts/test.sh --coverage`)
- [ ] Self-test passes (`swift run cellar selftest`)
- [ ] Wine tiers (`sh Scripts/test.sh --integration`) — for runners, prefixes, launching
- [ ] Real game (`sh Scripts/test.sh --steam`) — for depots, ownership, store credentials
- [ ] Ran it: the CLI command or the installed app — for anything a player sees

## Tests

<!-- Which tests this adds or changes, and what each would catch if the change broke. A change to
Swift under Sources/ must touch Tests/ — or replace this comment with one line saying why it can't:

No tests needed: <the reason, about this change>
-->

## Notes for the release

<!-- Anything a player should read in the release notes. Label the linked issue so it lands in
the right section; label this PR `skip-changelog` if it should not appear at all. -->
