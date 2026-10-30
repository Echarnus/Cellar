# Testing Cellar

Cellar sits on a stack it does not own — Wine, Rosetta, D3DMetal, three store clients — so "it
compiles" says almost nothing. The suite is arranged around that: a fast hermetic layer that runs on
every push, and an opt-in layer that actually translates Windows.

```sh
sh Scripts/test.sh                  # unit tests — fast, hermetic, no network. What CI runs.
sh Scripts/test.sh --coverage       # + line coverage, held to Tests/coverage-baseline.json.
sh Scripts/test.sh --integration    # + the Wine tiers: real runner, real prefix, real Windows game.
sh Scripts/test.sh --steam          # + tier D: download a real Steam game and run it.
sh Scripts/test.sh --filter Store   # anything else is passed straight to `swift test`.
```

> **Why a script and not `swift test`.** Two reasons. A Nix/devenv shell exports
> `DEVELOPER_DIR`/`SDKROOT` pointing at a non-macOS SDK — the same trap the rest of the repo works
> around by unsetting them. But tests need more than an SDK: `Testing.framework` ships only with a
> full **Xcode**, not with the Command Line Tools and not with the Nix SDK. `Scripts/test.sh` finds
> a developer directory that actually has it. If it can't, it says so rather than failing obscurely.
>
> First time on a machine: `sudo xcodebuild -license accept`.

---

## The strategy

The shape is the test pyramid every mature team converges on — many fast tests at the bottom, a few
expensive ones at the top — adapted to a product whose hardest dependency (Wine translating a
Windows game on a Mac) cannot run in a unit test:

| Layer | Where | Runs | Proves |
|---|---|---|---|
| **Unit** | `Tests/CellarKitTests` | every PR, seconds | decisions: parsing, routes, readiness, copy, the store table |
| **Rendered UI** | `Tests/CellarUITests` | every PR | store marks and views, drawn offscreen and measured |
| **Hermetic integration** | tier A + `FakeWine` | every PR | what Cellar writes to disk and hands to Wine; launch → watch → shut down |
| **Wine tiers** | tiers B and C | every PR (*Wine tiers* job) | a real runner, a real prefix, a real Windows exe |
| **A real game** | tier D | before a release | a real Steam depot downloaded and started |
| **Behaviour** | the installed app | before a release | the window, the click, the frame rate |

Three rules carry it, the same ones that make testing stick at teams that ship:

1. **Tests ride with the change.** No PR changes behaviour without a test that would catch the
   change breaking — enforced by a check, not by memory or goodwill. Reviewers (and the verifier
   agent) read the test before the code.
2. **The bar is the same for every author.** An AI agent's PR is held to exactly the human bar: it
   says which rungs it ran and shows the output. An agent that cannot run a rung (no Mac, no Steam
   account) says so, and that rung stays unticked for someone who can.
3. **The safety net only grows.** Coverage is ratcheted: it may rise and never fall. Not because a
   percentage proves correctness — it does not — but because a fall means new code arrived with no
   test at all, which is the one thing this policy exists to stop.

### Test doubles

Cellar's external world is processes and files, so its doubles sit at those boundaries rather than
behind protocols written only for tests:

- **The sandbox** (`TestHome`, `Scripts/test.sh`) — `CELLAR_HOME`, `CELLAR_PROFILES_DIR` and
  `CELLAR_APPLICATIONS_DIR` move every byte Cellar writes into a throwaway directory.
- **Profile fixtures** (`TestHome.writeProfile`/`plan`) — a game is a TOML string, resolved through
  the same `Game.plan` the app uses.
- **A fake game on disk** (`TestHome.installFakeGame`) — the bytes of a PE header where the profile
  says the exe lives, so "installed" is a fact Cellar finds rather than a flag a test sets.
- **The fake Wine** (`Support/FakeWine.swift`) — the stub runner's `wine` and `wineserver` become
  scripts that log their arguments and the Wine-relevant environment, and keep a fake game alive for
  as long as `<exe>.lifetime` says. `LaunchLifecycleTests` drives `Game.launch` and
  `Game.waitForExitThenShutDown` through it.
- **Recorded store state** — `loginusers.vdf`, `appmanifest_*.acf`, Battle.net's config and DepotDownloader
  output are tested as captured text, so a store parser is tested on what the store actually writes.

### Coverage and the ratchet

```sh
sh Scripts/test.sh --coverage
```

runs the suite with `--enable-code-coverage` and hands SwiftPM's report to `Scripts/coverage.py`,
which measures `CellarKit` and `CellarUI` (the executables cannot be imported by a test, so they are
not counted — keep logic out of them) and compares each with `Tests/coverage-baseline.json`. More
than 0.3 points below the baseline fails the run and names the least-covered files. CI writes the
table to the job summary on every run.

When a change raises coverage, lock it in within the same PR:

```sh
python3 Scripts/coverage.py --update .build/*/debug/codecov/*.json
```

`--update` only ever raises a number, so it cannot paper over a drop.

### What CI enforces on a PR

| Check | Job | Fails when |
|---|---|---|
| Build, tests, coverage | *Build & self-test* (macOS 15, macOS 26) | the build breaks, a test fails, coverage drops |
| The layer | *Wine tiers* | a real runner can't start and stop a Windows exe under Cellar |
| The description | *PR checklist* | no `Closes #N`, nothing ticked under *How it was verified*, or `Sources/` changed without `Tests/` |
| Hygiene | *Lint*, CodeQL, dependency review | see `docs/RELEASING.md` |

*Wine tiers* is reported on every PR but is not yet a required check: it downloads its runner from
upstream on every run, and a required check has to be one that only fails for a real reason. It
becomes required once it has run green across a week of PRs. The required set lives in
`.github/rulesets/main.json`, which is imported into the repository settings by hand.

---

## The tiers

| Tier | Switch | Cost | What it proves |
|---|---|---|---|
| **Unit** | always | < 1 s | Parsing, the store table, launch-route decisions, the readiness ladder and the words it shows. |
| **A — integration, hermetic** | always | ~1 s | Bottles, generated `.app` launchers, `shortcuts.vdf` — real files on disk, no Wine. |
| **B — the layer** | `CELLAR_IT=1` | ~1 min | A runner installs, a Wine prefix initialises as WoW64, a Windows PE runs and its output comes back. |
| **C — a game** | `CELLAR_IT=1` | ~2 min | A Windows-only game goes profile → bottle → launch → watched → shut down, through Cellar's own calls. |
| **D — a *real* game** | `CELLAR_IT_STEAM=1` | ~10 min + download | A game the player owns comes down from a real Steam depot, through `Game.fetchDepot`, and starts. |

Tiers B, C and D **skip** rather than fail when their switch is unset, and are reported as skipped —
a skip must never read like a pass. Tier D goes further and prints *why* on every run, because it is
the tier most likely to sit unrun: it needs an account, and no amount of correct code can supply one.

---

## What the unit suite covers

Everything that decides behaviour without touching Wine:

- **`ProfileParsingTests`** — the TOML reader: sections, comments, inline comments, values containing
  `=`, the `CELLAR_PROFILES_DIR` override that lets a player outrank a shipped profile.
- **`StoreTests`** — every spelling of `store = "…"`, the fallback for an unknown one, and the
  `StoreDescriptor` invariants: distinct accents, a total sort order, and the three differences that
  actually bite (Battle.net's non-silent installer, who can detect a sign-in, who signs in once).
- **`GamePlanTests`** — install-root search order, `directLaunchExe`, `canLaunchStoreFree`, the
  process needles that keep a game apart from its client, and the DRM-safe default of
  `needs_live_session`.
- **`GameSummaryTests`** — the readiness ladder and its copy. This is where `skills/ux.md` is
  enforced mechanically: Battle.net is never offered a sign-in step it cannot verify, every state has
  a full sentence, and the Play hint tells the truth about whether a client comes up alongside.
- **`SteamBottleTests` / `BattleNetTests` / `GOGTests`** — the state parsers. `loginusers.vdf`,
  `appmanifest_*.acf` and its `StateFlags`, Battle.net's config merge (which must not erase the
  player's own settings) and its account read (which must return *unknown*, never "nobody"), GOG's
  OAuth code extraction and multi-part installer selection.
- **`RunnerTests`** — the catalog's consistency, the runner-layout probe, and the Wine environment:
  that a stray `WINE*`/`DYLD_*` in the caller's shell is scrubbed, that Steam's overlay is always
  disabled, and that a profile's `WINEDLLOVERRIDES` is *merged* with the backend's rather than
  replacing it.
- **`CodecTests`** — CRC32 vectors, binary-VDF round trips including UTF-8 and truncation, stable
  shortcut appids, and the ASCII-QR reader.
- **`ProfileDatabaseTests`** — a lint over the profiles the repo ships: each one resolves, pins a
  real runner and a real backend, carries what its store needs to launch, declares
  `drm_circumvention = "never"`, and states a `status` the app has vocabulary for — with notes to
  back a `playable` claim.

### Test isolation

Cellar keeps all state under one root, so the tests move it: `CELLAR_HOME` relocates
`Paths.appSupport`, `CELLAR_PROFILES_DIR` the profile search, `CELLAR_APPLICATIONS_DIR` where
generated launchers land. A test run therefore cannot touch a real bottle, a real sign-in, or the
player's `~/Applications`. `CELLAR_HOME` is a real feature, not a test hook — it also gives you a
throwaway second installation.

The suites are `.serialized` on purpose: they install that environment once, from a lazy static, and
serialising removes any chance of a `setenv` racing a concurrent read.

---

## Tier C: running a Windows-only game

This is the test that answers the only question that matters — *does a Windows game start on this
Mac?* — and it does it through Cellar's own calls, not a hand-rolled Wine command line:

1. writes a `steam`, `needs_live_session = false` profile;
2. asserts Cellar offers **Install** and refuses to promise Play;
3. runs `Game.setUp` — runner, bottle, prefix, and no store client, said out loud;
4. drops the game's files where the profile says they are;
5. asserts the readiness ladder flips to **Play** and the hint now promises a store-free launch;
6. calls `Game.launch` and requires the `.direct` route;
7. **waits for the Windows process to appear** — the actual proof;
8. checks Cellar wrote the log a player would send in a bug report;
9. kills the game and asserts the whole layer comes down with it, wineserver included.

### Which game

By default it runs **`winemine.exe`**, the Win32 Minesweeper built into every Wine runner. That is a
deliberate choice: it is a genuine Windows PE, it is always present, it needs no download, and it
makes the pipeline provable on any machine and in CI. Cellar never commits a game file — the test
supplies the binary, Cellar supplies everything else.

To run a real title instead, point the test at one:

```sh
CELLAR_IT_GAME_URL='https://example.com/SomeSmallGame.zip' \
CELLAR_IT_GAME_EXE='SomeSmallGame/game.exe' \
sh Scripts/test.sh --integration --filter WindowsGameTests
```

| Variable | Meaning |
|---|---|
| `CELLAR_IT` | `1` to enable tiers B and C. |
| `CELLAR_IT_RUNNER` | Runner id to test against. Default: whatever is installed, else the catalog default. |
| `CELLAR_IT_GAME_URL` | A `.zip`, `.tar.*` or bare `.exe` to install into the bottle. |
| `CELLAR_IT_GAME_EXE` | Path of the executable inside it, relative to the install directory. |

The runner is **reused, not re-downloaded**: an installed runner tree is symlinked into the sandbox
read-only, so a test run never costs 400 MB and never writes into it.

---

## Tier D: a real Steam game — Fallout Shelter

Tier C is honest about being a fixture. `winemine.exe` is 100 KB, it ships inside Wine, and nothing
about running it resembles installing a game: no account, no depot, no engine, no shader
compilation. Tier D closes that gap by doing the thing a player does — authenticate to Steam, pull
the game down through **`Game.fetchDepot`**, and start it.

**The game is Fallout Shelter (app `588430`)**, and every part of that choice is load-bearing:

- **Free-to-play** — anyone with a Steam account can add it, so the tier is not gated on owning
  something expensive.
- **~2 GB** — small enough to download inside a test run.
- **Windows-only.** Steam publishes no macOS build, so a pass *cannot* be a native binary quietly
  running instead. Translation is the only way it can start on this Mac. This is the property that
  makes it evidence rather than a smoke test.
- **Single-player, no third-party DRM** — Steam publishes no `drm_notice` and no
  `ext_user_account_notice` for it — so it takes Cellar's store-free route and the test watches the
  game's own process instead of a client that spawned it.

It runs the profile the repo actually ships (`profiles/fallout-shelter.toml`), not a fixture. That is
the point: when this tier passes, that file is correct. Step 5 is the one worth knowing about — it
asserts the downloaded files match what the profile promised, so if Bethesda renames the executable,
Cellar finds out here rather than in a bug report.

```sh
cellar steam login              # once — a QR scan in the Steam mobile app, no password
sh Scripts/test.sh --steam
```

### It skips loudly

Ownership is asked of **Steam**, with the same credential that would do the downloading — so a
lapsed family-share or a region lock is caught before the download rather than halfway through it.
Free-to-play is exactly where this goes wrong: "free" reads like "everybody has it", and Steam still
refuses the depot until the account has actually added the game. When the tier cannot run it says so
as a sentence naming the fix:

```
[integration] Steam tier SKIPPED for fallout-shelter (app 588430): no Steam sign-in —
              run `cellar steam login` (one QR scan) and try again
```

| Variable | Meaning |
|---|---|
| `CELLAR_IT_STEAM` | `1` to enable tier D. Implies `CELLAR_IT` — it needs a runner and a prefix. |
| `CELLAR_IT_STEAM_APPID` | Steam app id to install. Default `588430`. |
| `CELLAR_IT_STEAM_SLUG` | Profile slug to run it through. Default `fallout-shelter`. |
| `CELLAR_IT_STEAM_INSTALLDIR` | The game's install directory name. Default `Fallout Shelter`. |
| `CELLAR_IT_STEAM_EXE` | The executable to launch and watch. Default `FalloutShelter.exe`. |

The download lands inside the throwaway `CELLAR_HOME` and goes with it, so the tier never touches a
real bottle — and never leaves 2 GB behind on a passing run.

### Running it unattended

The QR scan is the **only** interactive step, and it is not per run. DepotDownloader keeps a refresh
token that Cellar reuses silently for about **200 days** (`SteamAccount.expectedLifetimeInDays`), so
one scan buys months of unattended runs — a nightly job, a pre-release step, a self-hosted runner.

The sandbox makes that work by **copying** the machine's session in when the tier is on:
`shared/steam-account.json` and `tools/depotdownloader/` from the real
`~/Library/Application Support/Cellar` into the throwaway `CELLAR_HOME`. Copied rather than linked,
because the tool refreshes its token store as it works and a test must never write into the real
sign-in. `SteamAccount.state` is signed in only when *both* files are present, which is why both are
brought across.

Two things end the unattended run, and both say so in the log rather than failing quietly:

- **The token ages out.** Steam's refusal is reported as *"your Steam sign-in has expired"* and the
  tier skips. One scan resets the clock.
- **`cellar reset`** deletes `tools/depotdownloader` and `steam-account.json` on purpose — it is
  the *start over* command, and it lists "one QR scan to sign in again" as the cost. Don't reset the
  Mac that runs the tier, or budget a scan afterwards.

Using a dedicated Steam account for the runner is a reasonable choice — Fallout Shelter is free, so it
costs nothing — but it changes nothing above: it still signs in once, by QR, and its token ages the
same way.

---

## Where this sits in the verification ladder

`AGENTS.md` asks for the highest rung available before calling a change done. The suite maps onto it:

| Rung | Command |
|---|---|
| 1. Builds | `env -u DEVELOPER_DIR -u SDKROOT swift build -c release` |
| 2. Self-test | `swift run cellar selftest` |
| 2b. **Unit + tier A** | `sh Scripts/test.sh` |
| 2c. **Wine tiers** | `sh Scripts/test.sh --integration` |
| 2d. **A real game** | `sh Scripts/test.sh --steam` |
| 3. Behaviour | the CLI command, or `sh Scripts/install-app.sh` and launch the app |

`cellar selftest` stays: it is a check an *installed* binary can run on a player's machine, which a
test target cannot. The unit suite is the superset a developer runs.

CI runs rungs 1, 2 and 2b on every push, with coverage, on both macOS images, and rung 2c (the
*Wine tiers* job: Rosetta, the default runner, then tiers B and C) on every PR. A hosted runner has
no GPU worth translating to, so the Wine job proves that a Windows program starts and stops under
Cellar, not that a game is fast — rung 2d and rung 3 remain **the rungs a human climbs before a
release**.

---

## Adding tests

**Every PR that changes Swift under `Sources/` changes a test under `Tests/`**, and the test is one
that would fail without the change. A bug fix starts with the test that reproduces it. The *PR
checklist* check enforces this (a `No tests needed: <reason>` line in the PR body is the only way
past it, and the reason has to be about the change). Where the test goes:

- A change to how a game is *decided* about — profiles, stores, routes, readiness, copy — belongs in
  the unit suite, and needs no Wine.
- A change to what Cellar *writes* — bottles, app bundles, shortcuts, configs — belongs in tier A.
- A change to how a game is *run* belongs in tier B or C, behind `CELLAR_IT`.
- A change to how a game is *obtained* — depots, ownership, store credentials — belongs in tier D,
  behind `CELLAR_IT_STEAM`, and must skip with a sentence naming the fix rather than failing on a
  machine that is simply not signed in.
- Adding a game profile needs no new test: `ProfileDatabaseTests` picks it up automatically, and will
  tell you what it is missing.
