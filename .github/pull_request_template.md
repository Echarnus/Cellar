## What and why

<!-- What this changes, in a sentence or two, and why. -->

Closes #

## How it was verified

<!-- The highest rung of the verification ladder (AGENTS.md) this reached. -->

- [ ] Builds (`swift build -c release`)
- [ ] Tests pass (`sh app/Scripts/test.sh`)
- [ ] Self-test passes (`swift run cellar selftest`)
- [ ] Wine tiers (`sh app/Scripts/test.sh --integration`) — for runners, prefixes, launching
- [ ] Ran it: the CLI command or the installed app — for anything a player sees

## Notes for the release

<!-- Anything a player should read in the release notes. Label the linked issue so it lands in
the right section; label this PR `skip-changelog` if it should not appear at all. -->
