# Delivery checklist

Every line here is a yes/no question, and every one of them comes from a time Kenneth had to tell us
something we had delivered was broken. Nothing is called **done**, **fixed** or **playable**, and no
release is cut, until every line that applies is a **yes**, shown with evidence. A line that does not
apply is marked `n/a:` with the reason.

The PR template carries this list as its *Delivery checklist* section, and *PR checklist*
(`app/Scripts/check-pr.py`) fails a PR that changes app code, a profile or the shim while a box is
left unticked without an `n/a:` reason. The game checks are the baseline of `cellar verify <game>`
(#203), which runs on Kenneth's Mac with no one watching and writes a report under
`~/Library/Application Support/Cellar/verify/<slug>/<timestamp>/`. Its check IDs are the IDs below.

How a line is checked:

- **auto** — a test, a script or `cellar verify` answers it; quote the result.
- **mac** — Claude checks it on Kenneth's Mac itself (Remote Control), and pastes what it saw.
- Until `cellar verify` ships a check, its line is checked **mac**, with the commands given.

Never run a game on Kenneth's Mac while another thread is testing there, unless you have agreed it
with that thread.

## A. Every delivery

| ID | Yes when… | Checked by | Why it is here |
|---|---|---|---|
| A1 `proven` | The message that says "done" links evidence Claude produced itself: a `cellar verify` report, test output, a screenshot. It never says "should work now, please check". | the reply itself | "Workshop still didn't work", "still showing wine", "Nope, still crashing", "verify your work please" (Oct 31 – Nov 1) |
| A2 `his-bar` | Every done-criterion Kenneth stated for this work is met (project memory). A workaround that drops one, such as hiding DLC to stop a crash, is not a fix. | the criteria, line by line, against the report | PC2: all DLC, the Workshop, never the crash reporter (Nov 1) |
| A3 `prs-green` | Every PR from the work is green, conflict-free and merged by Claude. Kenneth never finds a red or conflicted PR. | auto: the PR's checks and mergeability on GitHub | "I notice merge conflicts" (Oct 30), "I still see PRs, they are failing" (Oct 31) |
| A4 `release-scope` | A release goes out only when everything Kenneth named for it passes its checks, and its notes call anything unchecked exactly that. | the release's linked issues against their reports | "I only wanted a release when the things I mentioned are fixed" (Nov 1), v0.4.0 shipping DLC and Red Dead untested |
| A5 `his-hands-only` | Kenneth is asked only for what needs his hands: a sign-in, a macOS permission prompt. Anything Claude can run on his Mac, it runs. | the reply itself | Terminal commands sent for the curl test, `dlc-check.py`, the runner restore; "Can you do for me?", "Test whatever you need locally" (Nov 1) |

## G. Anything that starts, signs in, downloads or runs a game

Run `cellar verify <game>` for every game the change can affect, at least Planet Coaster 2, Skyrim
and Fallout Shelter for a Steam-wide change.

| ID | Yes when… | Checked by | Why it is here |
|---|---|---|---|
| G1 `signed-in` | The game's Steam is signed in as the player's account and no Steam sign-in window ever appears. | auto: `cellar verify`. mac: `loginusers.vdf` in `shared/steam/config` names the account with `MostRecent "1"`, and no window titled *Sign in to Steam* is on screen | Skyrim asking to sign in while signed in; Steam no longer signing itself in after test launches (Nov 1) |
| G2 `steam-online` | Steam is online by its own connection log, not in offline mode. | auto: `cellar verify`. mac: the newest lines of `shared/steam/logs/connection_log.txt` | Fallout Shelter: no connectivity, Steam offline (Nov 1) |
| G3 `game-online` | The game's **own** process reaches its own servers (the Workshop, Bethesda.net…), and Wine logs no TLS or certificate error. A probe passing is not this. | auto: `cellar verify` (the game's open connections plus Wine's `secur32`/`crypt` errors) | Frontier Workshop unreachable while `cellar network` passed (#23, Oct 30 – Nov 1) |
| G4 `stays-up` | Several cold launches in a row each reach the game and stay up for the profile's survive time, with no crash reporter and no Wine crash. One lucky start is not a yes. | auto: `cellar verify` (`run-N.stays-up`) | PC2 showing Frontier's crash reporter, 1 good start in 16 (Nov 1) |
| G5 `dlc` | Every DLC the player owns is on disk and Steam reports it installed. | auto: `cellar verify`. mac: `steamapps/appmanifest_<appid>.acf` exists in the game's Steam library | DLC downloaded but invisible to the game (#185, Oct 31) |
| G6 `dock` | While playing, the Dock shows only Cellar and the game, under its display name ("Fallout Shelter", not `fallout-shelter` or `wine`), with no Steam icon; the game runs from its own `.app`, so Game Mode can turn on. | auto: `cellar verify`. mac: `lsappinfo list` shows the game's name and its `apps/<Name>.app` bundle, and no visible `wine` or Steam entry | "Still showing wine" (#178), "I dislike seeing Steam" (#200), dashed names (#219), Game Mode never on (#46) |
| G7 `clean-exit` | After the game quits, no Wine process is left for its bottle, and its page is back to Play within 30 seconds. | auto: `cellar verify`. mac: `pgrep -fl 'wine|\.exe'` after quitting | Wine processes left after quitting (#20); stuck on Playing (#174) |
| G8 `settings-match` | The bottle's settings match the profile and the Mac (the game's language is the Mac's language), unless the player changed them in Cellar. | auto: `cellar verify` | Metal validation switched off on PC2, the crash fix gone (Nov 1); Steam and PC2 in Dutch (Oct 30) |
| G9 `real-install-untouched` | Tests and verification left the real runners and bottles byte-for-byte as they were. | auto: the runner fingerprint `test.sh` and `cellar verify` take before and after (#204) | A test run overwrote the real WineForge with the fake Wine (#190) |

## P. Anything a player sees

| ID | Yes when… | Checked by | Why it is here |
|---|---|---|---|
| P1 `no-terminal` | Nothing the player is told to do needs Terminal, a script or editing a file. When something is broken, Cellar repairs it itself. | the copy and the release notes; auto: *PR checklist* fails a shell command in *Notes for the release* | "Can't expect end users to do that" about the runner restore command (Nov 1, fixed by #194) |
| P2 `plain-words` | Player screens never say bottle, runner, Wine, prefix, D3DMetal, log or profile. | auto: `GameMenuTests` jargon checks in `test.sh`; a screenshot of the changed screen | "Dumb it down. Users don't need to know about the technical part", "remove these for the users" (Oct 31) |
| P3 `own-state` | A game's page only ever shows that game's download, launch and play state. | auto: the per-game state tests (#196) in `test.sh`; a screenshot with two games | Skyrim saying Launching for PC2 (#195), Skyrim showing PC2's download (#172) |
| P4 `art-keeps-shape` | Every cover and banner keeps its proportions at every window size. | auto: the aspect tests in `CellarUITests` and `app/.build/ui-snapshots/`; a screenshot of a wide window | Stretched game images (#163) |
| P5 `responsive` | The app answers clicks straight away during and after a download or install. | mac: click through the library while a download runs, and after it ends | "App seemed to lag afterwards" (Oct 31, #172) |

## Adding a line

When Kenneth has to correct a delivery again, the fix is not finished until the correction is a line
here (or sharpens an existing one) and, wherever it can be, an automatic check in `cellar verify` or
`test.sh`. Give it the next ID in its group, and never reuse or renumber an ID: reports and PRs quote
them.
