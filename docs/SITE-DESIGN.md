# Site design guideline

The base the Cellar website is built on: <https://echarnus.github.io/Cellar/>. Read it before
changing anything in `pages/`. The site is built *from* this guideline: the tokens below are the ones
in `pages/gen-site.py`, and `pages/check-site.py` enforces what it can. A page that breaks a rule here
is not done, however good it looks.

The app has its own guide, [`DESIGN.md`](DESIGN.md). This one applies the same principles (Apple's
Human Interface Guidelines, plain words, honest state) to a marketing site, in Cellar's red-wine
colours. Where the two overlap, they agree. Where this one is silent, `DESIGN.md` decides.

---

## 1. What the site is for

**The site's goal is to be where a Mac owner lands when they search for how to play Windows games on
their Mac, and to leave them knowing they can.**

The reader owns a Mac with Apple silicon and a Steam library. They are not technical, and they have
probably been burned before by a forum thread that ended in Terminal. They need three answers in
order:

1. **Can I play my games on this Mac?** Steam games, Apple silicon, free.
2. **What is it like?** One sign-in, one button, a real Mac app.
3. **Will *my* game work?** Every game says what is known about it, and which Mac it needs.

Every page and every section exists to answer one of these. Anything that doesn't is cut.

## 2. Principles

Apple's three HIG themes, applied to a page, plus the two rules Cellar adds.

| Principle | On the site |
|---|---|
| **Clarity** | One message per section, said in its headline. One action per page: **Download for Mac**. Facts beat adjectives: "M1, 8 GB" rather than "runs great". |
| **Deference** | The product and the games lead; the page recedes. Pictures are the app in a Mac window and the games' own cover art. Chrome is quiet: hairlines, not boxes. Wine is an accent, not a background. |
| **Depth** | Used sparingly and only where it means something. The translucent bar sits *over* the page. A product window has a shadow because it is an object. Flat things (text, lists) never get one. |
| **Honesty** (Cellar) | Never claim more than is known. "Untested" is said plainly, on the card and on the game's page. A missing screenshot is a labelled placeholder, never a mock-up. Other platforms' ratings are labelled as theirs. |
| **Restraint** (Cellar) | A new thing replaces something. Adding is not free: each section has to earn its place against the reader's three questions (§1). The home page has at most **seven** sections. |

## 3. Colour

Two appearances, light and dark, both following the system unless the visitor picks one. All values
live in `LIGHT`, `DARK` and `DEEP` in `gen-site.py`, and `check-site.py` measures every text pair
against WCAG 2.2 AA (4.5:1 for text, 3:1 for focus rings). A palette change that fails it does not
ship.

| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#fbf8f7` | `#121014` | The page. Warm white, warm black. |
| `surface` | `#ffffff` | `#1c181c` | Inside a product window, inputs. |
| `surface-2` | `#f3eded` | `#262026` | A quiet field (the "Free" band), the footer, a window's title bar. |
| `fg` | `#1c1a1d` | `#f4eff1` | Headlines and body. |
| `muted` | `#5f5960` | `#b0a8ae` | Secondary text: ledes, captions, facts' labels. |
| `line` | `#e4d9da` | `#352c32` | Hairlines between rows. |
| `primary` | `#8e1f3d` | `#b02e57` | **The wine.** The Download button, and nothing else filled. |
| `link` | `#9b2546` | `#f59ab5` | Links, focus ring, the small glyphs in the details grid. |
| `deep` | `#1c0b12` | same | The one dark section per page (the launch steps). White type. |
| `ok` / `warn` / `untested` | green / amber / grey | lighter | Game status, always with a word beside it. |

**How much wine.** Roughly one part in twenty: the Download button, links, the app icon, one soft
glow behind the hero window, and the deep band. Headlines are never wine. Never a wine gradient
behind text. If a screen looks red, there is too much.

**Colour never carries meaning alone.** A status is a dot or badge *and* its word. A store, when there
is more than one, is a mark *and* its name.

## 4. Typography

The system font: SF Pro on Apple devices (`-apple-system`), falling back to the platform's own. Three
weights only: **400** (body), **600** (titles inside content), **700** (headlines). Tracking tightens
as size grows, as SF's does.

| Token | Size | Weight | Line height | Tracking | Use |
|---|---|---|---|---|---|
| `display` | `clamp(44px, 7vw, 76px)` | 700 | 1.05 | −0.015em | The hero headline. One per page. |
| `title-1` | `clamp(32px, 5vw, 52px)` | 700 | 1.08 | −0.015em | Section headlines. |
| `title-2` | `clamp(26px, 3vw, 32px)` | 700 | 1.14 | −0.012em | A feature row's headline. |
| `title-3` | `20px` | 600 | 1.25 | −0.01em | Items in grids, FAQ questions. |
| `lede` | `clamp(19px, 2.2vw, 23px)` | 400 | 1.38 | −0.01em | The sentence under a headline, in `muted`. |
| `body` | `17px` | 400 | 1.47 | −0.022em | Everything else. Apple's own body size. |
| `footnote` | `14px` | 400 | 1.43 | −0.01em | Captions, the line under the Download button. |
| `caption` | `12px` | 400 | 1.33 | 0 | The footer. |

Rules:
- **Headlines are sentences**, in sentence case, ending in a full stop. "Your games are waiting."
- **Buttons and the nav are Title Case**, as in the app ("Download for Mac", "See It Work").
- No uppercase eyebrows, no letter-spaced kickers. A headline introduces itself.
- A text column is never wider than ~70 characters; ledes ~44.

## 5. Layout and spacing

An **8-point grid**. Spacing tokens: `4 8 12 16 24 32 48 64 96 120`. Nothing in between.

- **Content width** 1068 px with 22 px gutters; a centred text column is 760 px.
- **Sections are separated by space**, not by borders or boxes: 120 px between sections on a wide
  screen, 80 px on a phone. A change of background (the deep band, the quiet field) is the only
  other divider.
- **Breakpoints:** 540 (phone: game cards become rows), 760 (nav moves into the bar), 900 (two-column
  feature rows).
- Every page works at **320 px** wide without sideways scrolling, and every target is at least
  **44 × 44 px**.

## 6. Shape and depth

- **Radii:** 8 (small controls, chips), 12 (windows, covers, inputs), and **980** for the pill: the
  primary button, and badges. Nothing else is rounded.
- **Hairlines** (1 px `line`) separate rows in lists: the details grid, the FAQ, the spec list, the
  footer. Never a full border around a block of text.
- **Shadows** only on objects: product windows and game covers. Never on text, cards of text, or
  buttons.
- **Translucency** only on the top bar (`saturate(180%) blur(20px)`), so the page shows through it.

## 7. Components

Each is built once in `gen-site.py` and reused. A new page composes these; a new component needs a
reason a current one cannot serve.

| Component | What it is | Rules |
|---|---|---|
| **Top bar** | Icon + "Cellar", nav links, appearance toggle, small Download pill. | 52 px tall, translucent. Links 14 px `muted`, the current page in `fg`. |
| **Primary button** | Filled wine pill, white label, optional download glyph. | Once per view. "Download for Mac" always means the same file. |
| **Chevron link** | A text link ending in `›`. | The secondary action beside the primary button, and "more" links. Never a second filled button. |
| **Product window** | A Mac window (three grey dots, title bar) around a real capture. | The only frame a screenshot ever gets. Shadow + one glow allowed. |
| **Placeholder window** | The same window, a "Coming soon" tag, and what the capture will show. | Says it is a placeholder. Never drawn to look like the app. Swapped by dropping the file into `pages/media/` (`docs/SHOWCASE.md`). |
| **Feature row** | Headline + two or three sentences beside a product window, sides alternating. | One idea per row. Bold only the one fact a skimmer must catch. |
| **Launch steps** | The deep band with the app's own launch steps, ticking in turn. | Words copied from `LaunchStage.swift`, which a test enforces. Becomes the screen recording when it exists. |
| **Details grid** | Small glyph + `title-3` + one or two sentences, hairline above. | No boxes, no tinted icon tiles. Glyphs are 1.8-stroke line icons in `link`. |
| **Statement band** | One centred headline on `surface-2` with three short columns. | For the promise (free, open, private). At most one per page. |
| **Game card** | Cover (2:3), status badge, name, the Mac it needs. Links to the game's page. | The cover is the game's real art. Facts stay short; the game page has the rest. |
| **Game page facts** | A two-column spec list with hairlines. | Labels in `muted`, values in `fg`. "Not stated" where a fact is unknown, never a guess. |
| **Segmented control + search** | Filters on the games list. | Equal-width segments with counts, as in the app (`DESIGN.md`). |
| **Disclosure row** | A FAQ question that opens its answer. | Hairline rows, chevron on the right, no boxes. |
| **Footer** | Link columns, then the legal line and the credits. | 12 px. Credits every outside source the site's facts come from (§10). |

## 8. Motion

Quiet and functional. Transitions are 150–250 ms ease. The launch steps are the only thing that
moves by itself, because they show something real: the order Cellar works in. Under
`prefers-reduced-motion`, nothing moves and the steps show as done.

## 9. Words

The voice is a knowledgeable friend: plain, concrete, second person, short sentences. Read
[`skills/ux.md`](../skills/ux.md); these are the site's additions.

- **Say the fact, not the feeling.** "Each game names the slowest Apple chip it should run on", not
  "know exactly what to expect".
- **Lead with Steam and the Mac.** The reader searches "Steam games on Mac", so the page says it.
- **No jargon** (`DESIGN.md` §2): no Wine, runner, prefix, D3DMetal, DXVK, profile, depot or log on
  the home, games, game and 404 pages. `check-site.py` fails the build if one slips in. **"Bottle"
  is allowed:** it is the cellar wordplay, and the app says it.
- **Phrases that read as generated, and are banned:** "seamless(ly)", "effortless(ly)", "gets out of
  your way", "everything you need", "unleash", "supercharge", "game-changer", "the way it likes",
  "not just X, but Y", and a run of three negatives ("no X, no Y, no Z") as a selling point.
- **Numbers are honest.** Never lead with a count that makes the product look weaker than it is
  ("2 of 49 confirmed"), and never hide it either: the games list says what is confirmed.
- **Free means free.** Never "free for now", never a price, never a locked feature. Sponsoring is
  mentioned once, quietly, near the end.

## 10. Credits

Every outside source a fact on the site comes from is named in the footer, with a link, and on a game
page beside the fact it supports (Kenneth, 2026-11-03). Today: Wine; ProtonDB, Valve's Steam Deck
ratings, AreWeAntiCheatYet, PCGamingWiki, AppleGamingWiki, the CodeWeavers Compatibility Center and
SteamDB; Steam for cover art. A new source gets credited in the same change that adds it, here and
in the app (`Credits.sources`).

## 11. Pages

| Page | Purpose | Sections, in order |
|---|---|---|
| **Home** (`index.html`) | Answer §1's three questions and get the download. | Hero (headline, lede, Download, the app in a window) → what it does (four feature rows) → press Play (launch steps) → the details (grid) → the games (exactly ten, a search box and a link that open the games page) → free (statement + sponsoring) → closing call. |
| **Games** (`games.html`) | Find your game. | Headline, search and filters, every game, "Don't see your game?". |
| **A game** (`games/<slug>.html`) | Answer "will *this* game work on my Mac?", and rank for "<game> on Mac". | "<Game> on Mac" headline and its status in a sentence, cover + facts (the Mac it needs, what is known), what other platforms report (credited), how to play it in three steps, Download. |
| **Questions** (`faq.html`) | Everything else, including the technical "how". | Contents + grouped disclosure rows. The one page allowed to explain the plumbing. |
| **404** | Get back. | Headline, one sentence, two links. |
| **Sponsor** (`sponsor.html`) | Say openly what sponsoring buys (#299). | Headline, why every chip matters, the tiers (spec grid), "Bought so far", the promise (statement band), how to help. Payment links come from `SPONSOR_LINKS` in `gen-site.py`; empty, it says "Sponsoring Opens Soon". The home page only links here. |

## 12. Search engines and sharing

The site should be the answer to "play Windows games on Mac", "Steam games on Mac" and "<game> on
Mac". Built in, not bolted on:

- **One `<h1>` per page** that says what the page is, in the words people search: "Play your Windows
  Steam games on your Mac.", "Planet Coaster 2 on Mac".
- **Titles** `<What the page answers> — Cellar`, under 60 characters. **Descriptions** 120–160
  characters, a real sentence with the key words, unique per page.
- **Canonical URL**, Open Graph and Twitter card on every page, with a large share image.
- **Structured data** (JSON-LD): `SoftwareApplication` on the home page, `FAQPage` on the FAQ,
  `BreadcrumbList` and a `VideoGame` on each game page.
- **`sitemap.xml`** lists every page, game pages included; `robots.txt` points at it.
- **Fast by construction:** static HTML, one inlined stylesheet, a few lines of plain JavaScript, no
  framework, no web fonts, images with their size and `loading="lazy"`.
- **Semantic HTML** (landmarks, headings in order, `alt` on every image, labels on every input), which
  is also what assistive technology needs. `check-site.py` checks it.

## 13. Accessibility

WCAG 2.2 AA, checked by `check-site.py` where a machine can: contrast of every palette pair, one `h1`,
no skipped heading level, `alt` on images, labelled inputs, typed and named buttons, captions on
video. By hand: keyboard order, a visible focus ring (3 px `focus`), 44 px targets, both appearances,
`prefers-reduced-motion` and `prefers-contrast`.

## 14. Checking a change

1. `python3 pages/gen-site.py && python3 pages/check-site.py`, with both TOML parsers
   (`CELLAR_TOML_FALLBACK=1`), as CI does.
2. `python3 -m unittest discover -s app/tests/Scripts` (the site's tests are there).
3. Open `pages/dist/index.html` in light and dark, and at 390 px. Look at it; a diff says nothing
   about how a page looks.
4. Put before and after screenshots in the PR.
