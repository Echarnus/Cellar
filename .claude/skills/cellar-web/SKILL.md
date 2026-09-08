---
name: cellar-web
description: Best practices for the Cellar static site — the HTML, CSS and JS of the GitHub Pages landing page. Use when changing how the page looks or is structured. Covers the data-driven-from-profiles rule, the versionless Cellar.dmg download link, the no-build-step constraint, the Apple-calibre theme/responsive/accessibility bar, and measuring accessibility rather than eyeballing it. For the generator itself, use cellar-python.
---

# Cellar — web / static site

The full guide is [`skills/web.md`](../../../skills/web.md); read it. Key rules:

- The site is **generated** by `Scripts/gen-site.py` into `site/index.html` — no framework, no build
  step, inline CSS/JS. Edit the **generator**, not the HTML.
- **Data-driven:** the games grid comes from `profiles/*.toml` — change the generator to change a
  card. Keep `gen-site.py` **Python 3.9-safe** (tomllib + fallback parser).
- **Download CTA** links to the **versionless** `releases/latest/download/Cellar.dmg` — don't add a
  version to that filename.
- **Quality bar:** semantic HTML, theme-aware via `:root` custom properties (+ `prefers-color-scheme`
  dark), responsive (no horizontal body scroll), accessible (focus states, WCAG AA contrast,
  `prefers-reduced-motion`), self-contained.
- **Verify by rendering, then measure:** `python3 Scripts/gen-site.py`, open `site/index.html`, check
  title, Download CTA, one card per profile, icon present, light+dark, narrow width. Then *measure*
  the accessibility claims — contrast ratios in devtools (**≥ 4.5:1** body, **≥ 3:1** large text and
  UI), tab through every control, one `<h1>` and real `alt` text, reduced motion honoured. An
  automated pass (axe/Lighthouse) catches these in seconds.
- The generator's own rules — stdlib-only, Python 3.9 floor, escaping, encoding — live in
  [`cellar-python`](../cellar-python/SKILL.md).

Before reporting done, run the **cellar-verifier** agent.
