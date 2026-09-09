# Testing Cellar

Cellar sits on a stack it does not own — Wine, Rosetta, D3DMetal, three store clients — so "it
compiles" says almost nothing. The suite is arranged around that: a fast hermetic layer that runs on
every push, and an opt-in layer that actually translates Windows.

```sh
sh Scripts/test.sh                  # unit tests — fast, hermetic, no network. What CI runs.
sh Scripts/test.sh --integration    # + the Wine tiers: real runner, real prefix, real Windows game.
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

## The tiers

| Tier | Switch | Cost | What it proves |
|---|---|---|---|
| **Unit** | always | < 1 s | Parsing, the store table, launch-route decisions, the readiness ladder and the words it shows. |
| **A — integration, hermetic** | always | ~1 s | Bottles, generated `.app` launchers, `shortcuts.vdf` — real files on disk, no Wine. |
| **B — the layer** | `CELLAR_IT=1` | ~1 min | A runner installs, a Wine prefix initialises as WoW64, a Windows PE runs and its output comes back. |
| **C — a game** | `CELLAR_IT=1` | ~2 min | A Windows-only game goes profile → bottle → launch → watched → shut down, through Cellar's own calls. |

Tiers B and C **skip** rather than fail when `CELLAR_IT` is unset, and are reported as skipped —
a skip must never read like a pass.

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

1. writes a `standalone`, `needs_live_session = false` profile;
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

## Where this sits in the verification ladder

`AGENTS.md` asks for the highest rung available before calling a change done. The suite maps onto it:

| Rung | Command |
|---|---|
| 1. Builds | `env -u DEVELOPER_DIR -u SDKROOT swift build -c release` |
| 2. Self-test | `swift run cellar selftest` |
| 2b. **Unit + tier A** | `sh Scripts/test.sh` |
| 2c. **Wine tiers** | `sh Scripts/test.sh --integration` |
| 3. Behaviour | the CLI command, or `sh Scripts/install-app.sh` and launch the app |

`cellar selftest` stays: it is a check an *installed* binary can run on a player's machine, which a
test target cannot. The unit suite is the superset a developer runs.

CI runs rungs 1, 2 and 2b on every push. The Wine tiers are not run in CI — a GitHub runner has no
GPU worth translating to and no reason to download a Wine build — so **they are the rung a human has
to climb before a release**.

---

## Adding tests

- A change to how a game is *decided* about — profiles, stores, routes, readiness, copy — belongs in
  the unit suite, and needs no Wine.
- A change to what Cellar *writes* — bottles, app bundles, shortcuts, configs — belongs in tier A.
- A change to how a game is *run* belongs in tier B or C, behind `CELLAR_IT`.
- Adding a game profile needs no new test: `ProfileDatabaseTests` picks it up automatically, and will
  tell you what it is missing.
