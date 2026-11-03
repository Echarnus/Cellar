# Compatibility estimates

How Cellar says whether a game nobody has tested is likely to work (#286).

## The problem

Of 33 shipped profiles, 31 say `untested`, and Kenneth cannot play every game. "Untested" alone
tells a player nothing: Stardew Valley (DirectX 9, no anti-cheat, Platinum on Linux) and Elden Ring
(DirectX 12 only, Easy Anti-Cheat) read the same. Every game Cellar ships should carry an
evidence-based expectation, said plainly, with its reasons one level down.

## The rules

1. **A test always wins.** `status = "playable"` (a `cellar verify` pass) shows **Works**;
   `broken` shows **Doesn't work yet**. Nothing below can override a test.
2. **An estimate always says it is one.** The badge reads "Should work · Not tested", never a
   bare "Works", and never a ✓ (`docs/DESIGN.md`, honesty).
3. **Hard blockers decide alone.** An anti-cheat that only accepts Windows itself (Vanguard,
   FACEIT, Ricochet, nProtect, XIGNCODE, anything kernel-level) is **Won't work**, however well
   everything else looks.
4. **Otherwise the facts are weighed**, each adding or taking a little (table below), and the sum
   picks the outlook: 4 or more **Should work**, 1 to 3 **Might work**, 0 or less **Unlikely to
   work**.
5. **Thin evidence never says "Should work".** An estimate needs at least two independent kinds
   of evidence (known graphics, public reports, a lesson Cellar learned on a game built the same
   way). With fewer, the best it says is **Might work**.
6. **Online play gets its own sentence** when it differs from the rest of the game: an anti-cheat
   that guards only online play costs the estimate a little, and says separately that online play
   hasn't been seen working.

## What is weighed

| Fact | Source | Weight |
|---|---|---|
| DirectX 11 | profile `graphics_api` | +2 |
| DirectX 9 / 10 | profile | +1 |
| DirectX 12 | profile | 0 (one way to run it on a Mac) |
| Vulkan | profile | −1 |
| A second graphics option to fall back to | profile `fallback_backend` | +1 |
| No anti-cheat, or Valve's (VAC) | profile `anticheat` | +1 |
| Easy Anti-Cheat / BattlEye for online play only | profile | −1, plus the online sentence |
| Easy Anti-Cheat / BattlEye needed to start | profile | −3 |
| Kernel-level anti-cheat | profile | blocks: Won't work |
| EA app, Ubisoft Connect, Epic launcher needed | profile `drm` | −2 (Cellar can't set them up) |
| Rockstar Games Launcher | profile `publisher_launcher` | note: Cellar sets it up (#267) |
| Denuvo | profile `drm` | note: may count the Mac as a new PC |
| Creation Engine / Gamebryo, on the D3DMetal 4 runtime | Cellar lesson #246 (Skyrim) | +1, else −1 |
| Frontier's COBRA engine | Cellar lesson #261 (patched wineserver, PC2 Workshop) | +1 |
| Mac players report it runs / runs with problems / fails (CrossOver, Whisky) | `mac_reports`, by hand from a report named in `notes` | +2 / +1 / −4 |
| ProtonDB Platinum / Gold / Silver / Bronze / Borked | `protondb` | +3 / +2 / +1 / 0 / −3 |
| Steam Deck Verified or Playable / Unsupported | `steam_deck` | +1 / −1 |
| Anti-cheat runs on Linux (AreWeAntiCheatYet) | `anticheat_on_linux` | note only (below) |

**Why Linux evidence counts, and how far.** Valve's Proton is Wine, the same layer Cellar runs a
game through, so a game that runs well on Linux has cleared most of what stops a Windows game
outside Windows: its installer, its DRM, its launchers, its use of the Windows API. It differs in
graphics (Proton uses DXVK/VKD3D on Vulkan; Cellar prefers D3DMetal on Metal) and in anti-cheat:
Easy Anti-Cheat and BattlEye run on Linux through a module only Linux has, so "supported on
Linux" says little about a Mac and is shown as a note, not weighed. A publisher that *denies* its
anti-cheat outside Windows is still decisive for online play.

## Where the evidence lives

In the profile's `[compatibility]` section, as flat scalars like every other field
(`skills/profiles.md`):

```toml
protondb                    = "gold"
steam_deck                  = "verified"
anticheat_on_linux          = "supported"
evidence_checked            = "2026-11-03"
```

`mac_reports = "runs" | "issues" | "fails"` sits beside them: what Mac players report running the
game through another Wine-based app. No source publishes that in a form a script can read, so it is
written by hand, and only from a report the profile's `notes` names. It outweighs the Linux
evidence: Enshrouded is Gold on Linux, but Mac players see it stop at start, so it is "Unlikely to
work".

`app/Scripts/refresh-evidence.py` writes them from ProtonDB's summary API, Valve's Steam Deck
report and AreWeAntiCheatYet's `games.json`, by Steam AppID. A source that can't be reached keeps
its old value, so a network failure never wipes evidence. `.github/workflows/evidence.yml` runs it
every Monday and prints the diff; a pull request brings it in. Because it lives in the profiles,
it reaches players with the next profile update, without an app release.

## Credit where it's due

Every source above is credited in Settings › About and named in the About panel
(`Credits.sources`), with the terms its data comes under (`THIRD_PARTY_LICENSES.md` → *Data
sources*): ProtonDB's data is ODbL, AreWeAntiCheatYet is MIT, the wikis are CC BY-NC-SA. Adding a
source means adding its `Credit` in the same PR; `CreditsTests` fails otherwise.

## Where it shows

- **Game page**: the badge beside the game's state ("Might work · Not tested"), with the one-line
  basis as its tooltip.
- **Technical Details**: *What Cellar expects*, one line per fact with where Cellar learned it.
- **CLI**: `cellar profiles forecast` lists every game, least likely first, which is the order to
  test them in. `cellar profiles forecast <slug>` gives every reason.

The code: `CompatibilityForecast`, `CompatibilitySignals` and `CompatibilityEvidence` in
`app/Packages/CellarDomain/Sources/CellarDomain/Compatibility/`, tested by
`CompatibilityForecastTests`.

## Adding a lesson

When a fix teaches Cellar something about a kind of game (an engine, a launcher, an anti-cheat),
add it to `CompatibilityForecast` with the issue as its `source`, and a test in
`CompatibilityForecastTests`, in the same PR as the fix. That is how a lesson from one game reaches
every game built the same way.

## Not yet

- Players' own reports (`compatibility-report` issues) are not counted automatically yet. They
  are the best Mac evidence there is, and the next step is to tally them per game into the same
  fields.
- The website still shows only the tested status; it should show the same estimate.
- Draft profiles (games Cellar wrote a profile for itself) get the estimate from what their files
  say, without public reports until a refresh can look them up at runtime.
