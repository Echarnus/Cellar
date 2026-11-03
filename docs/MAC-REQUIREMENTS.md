# Which Mac a game needs

Every game in Cellar says two Macs (#298):

- **Minimum** — the Mac the game starts and plays on, at low settings.
- **Recommended** — the Mac for a decent experience: a smooth game at good settings. This is the
  tag on the game page: *Best on M2 Pro or better*.

The game page lists both, with the other kinds of Mac that draw as well ("M5 · 24 GB memory, or an
M2 Pro or M1 Max"), and a line saying how *this* Mac compares. The site's game cards show both as
*Needs* and *Best on*. It sits beside the compatibility estimate (`docs/COMPATIBILITY.md`): that
one says whether a game runs at all, this one says on which Mac it runs well.

It is an estimate from the publisher's own numbers, not a test, and every sentence about it says so.

## Where the numbers come from

A profile records the publisher's PC requirements in its `[mac]` section, as the publisher wrote
them: the graphics card and memory for the minimum and the recommended PC. Cellar's rule turns
those into Macs, the same way for every game:

1. **The card's graphics score.** `PCGraphicsCard.all` places every card a profile names on one
   scale, where the M1's 8-core GPU is 100. The scale is anchored on Notebookcheck's comparisons
   (an M1 reaches about half a desktop GTX 1660 in games) and the cards are placed against each
   other by their relative performance in the same comparisons.
2. **The translation overhead.** A Windows game on a Mac runs through Wine, D3DMetal or DXVK, and
   Rosetta for the game's own code. Measured ports and CrossOver comparisons put the cost around a
   quarter to a third of the frame rate, so the card's score is multiplied by
   `MacRequirements.overhead` (1.3).
3. **The chip.** `MacChip.known` scores Apple's chips on the same scale (Notebookcheck and Apple's
   generation-over-generation figures). The requirement is the weakest chip that covers the
   overhead-adjusted score *and* that Apple sells with enough memory.
4. **The memory.** A Mac has one pool of memory for the game and its graphics, so the requirement
   is the PC's memory plus the card's own video memory, rounded up to a size Apple sells.

`MacRequirements.derive(card:memoryGB:)` is that rule. The chips are ranked by their graphics, not
their names: an M1 Max draws more than an M4, so a game best on an M4 is fine on an M1 Max, and
the page says so. A chip newer than Cellar knows is vouched for by the chips it replaced (Apple has
never shipped a successor that draws less), and where nothing can vouch for it, the page says
nothing about it rather than guess.

These are brackets, not frame rates. When a game has been played on a Mac, its `notes` say which
Mac and how it ran, and that is the better evidence.

## The rule for profiles (enforced)

Every profile has a `[mac]` section. A profile without one fails CI: `MacRequirementsTests` in the
app's tests, and `pages/gen-site.py`, which refuses to build the site. The section looks like this
(`planet-coaster-2.toml`):

```toml
[mac]
pc_requirements_source = "Steam store page, read through System Requirements Lab"
pc_gpu_minimum         = "GeForce GTX 1060"
pc_memory_minimum      = 16
pc_gpu_recommended     = "GeForce RTX 2070 Super"
pc_memory_recommended  = 16
mac_minimum            = "M5"
mac_memory_minimum     = 24
mac_recommended        = "M3 Max"
mac_memory_recommended = 24
requirements_checked   = "2026-11-03"
```

- **`pc_*` are the publisher's numbers**, copied from the store page or the publisher's own
  requirements page. Where they name an NVIDIA and an AMD card, use the NVIDIA one. Name where you
  read them in `pc_requirements_source`, and the date in `requirements_checked`.
- **No recommended spec published?** Some publishers list only a minimum. Use the minimum for both,
  or, where the minimum is a class of card no one plays on any more (Team Fortress 2's "DirectX 8.1
  card"), pick a card and say in `pc_requirements_source` that the pick is Cellar's.
- **A card Cellar doesn't know** fails the test with its name. Add it to `PCGraphicsCard.all` with
  a score placed against its neighbours from a public benchmark, and its video memory. Never pick a
  near card to dodge the table.
- **`mac_*` are what the rule gives.** The test fails with the rule's answer when they differ; copy
  it. A profile may ask for *more* than the rule, never less, and then says why in `mac_reason`
  (Grand Theft Auto IV: its port leans on the processor far harder than its card suggests).
- **A newer chip** (an M5 Pro, say) is added to `MacChip.known` once its graphics have public
  benchmarks. Until then players with one still get a verdict through the chips it replaced.

## Sources, credited

The publisher figures were read from the publishers' store and support pages, through System
Requirements Lab, PCGamesN, Pindrop, Beebom, GameRequirementsLab and PCGameBenchmark where the
store page itself was out of reach; the graphics scale is from Notebookcheck's benchmarks. Every one
of them is named in Settings › About (`Credits.sources`), per Kenneth's rule that external sources
are credited.
