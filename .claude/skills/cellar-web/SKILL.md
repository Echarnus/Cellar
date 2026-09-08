---
name: cellar-web
description: Best practices for the Cellar static site — HTML, CSS, JS. Use when editing Scripts/gen-site.py or anything about the GitHub Pages landing page. Covers the data-driven-from-profiles rule, the versionless Cellar.dmg download link, no-build-step constraint, and the Apple-calibre theme/responsive/accessibility bar.
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
- **Verify by rendering:** `python3 Scripts/gen-site.py`, open `site/index.html`, check title,
  Download CTA, one card per profile, icon present, light+dark, narrow width.

Before reporting done, run the **cellar-verifier** agent.
