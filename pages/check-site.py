#!/usr/bin/env python3
"""Check the generated site before it ships: links, structure, and the contrast of its palette.

Run after pages/gen-site.py:  python3 pages/check-site.py [--external] [site-dir]

Fails (exit 1) on:
  - a relative link, image or anchor that points at nothing in the site
  - a link into this repository's main branch (…/blob/main/<path>) whose file does not exist here
  - structure: not exactly one <h1>, a skipped heading level, an <img> without alt, a duplicate
    id, an <input> without a label, a <button> without a type or an accessible name, a missing
    lang or <title>, template text that leaked into the page ({…}), or copy implying a game
    can come from no store, or that names a store the site does not offer yet (gen-site.py's
    OFFERED; the first release is Steam only) outside a game card's own profile facts
  - a technical word (Wine, bottle, runner, D3DMetal, profile…) in the player-facing copy of the
    home, games, sponsor or 404 page (docs/DESIGN.md §2; the FAQ explains them, and the footer credits Wine)
  - a <video> without a poster and an English captions <track>, or a screenshot or video in
    media/ larger than MEDIA_LIMITS
  - a game card whose cover has no <img> (every game ships real cover art; the generated
    placeholder is only what shows if the image fails to load)
  - any palette pair in gen-site.py's CONTRAST table under its WCAG 2.2 AA ratio
With --external, also every other http(s) <a href> and every game card's cover image, failing on
404/410 only: a network error or a
rate limit says nothing about the link, so it is reported and not failed.

Standard library only, Python 3.9 floor, like the generator (skills/python.md).
"""
import argparse
import glob
import html.parser
import importlib.util
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# docs/DESIGN.md §2: a player never reads the plumbing. Checked on the pages a player lands on;
# faq.html has a question that explains these words, and the footer's credit names Wine.
PLAIN_PAGES = ("index.html", "games.html", "sponsor.html", "404.html")
JARGON = re.compile(r"\b(wine|bottles?|wineprefix|prefix(es)?|runners?|d3dmetal|dxvk|moltenvk|"
                    r"profiles?|manifests?|depots?)\b", re.I)
# Bytes per file in media/, so a capture can't make the page slow to open (skills/web.md: Fast).
MEDIA_LIMITS = {".png": 600_000, ".jpg": 600_000, ".mp4": 15_000_000, ".vtt": 50_000}


def load_generator():
    spec = importlib.util.spec_from_file_location("gen_site", os.path.join(ROOT, "pages", "gen-site.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Page(html.parser.HTMLParser):
    OFFERED, HIDDEN = (), ()  # names of the stores the site does not offer yet, set from gen-site.py's OFFERED
    VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids, self.links, self.headings, self.problems = [], [], [], []
        self.labels_for, self.inputs = set(), []
        self.lang = None
        self.videos = []       # [line, has poster, has English captions]
        self.title = ""
        self._in = []          # open element stack
        self._button = None    # [attrs, text] of the button being read
        self._raw = 0          # inside <script>/<style>
        self.covers = []       # [line, cover src or None] per game card's .art
        self._art = None       # stack depth of the .art being read
        self._card = None      # stack depth of the game card being read
        self.plain = False     # hold the copy to PLAIN_PAGES' rule
        self._exempt = None    # stack depth of a .legal credit or a card's profile facts

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        line = self.getpos()[0]
        if "id" in a:
            self.ids.append((a["id"], line))
        if tag == "html":
            self.lang = a.get("lang")
        if tag in ("script", "style"):
            self._raw += 1
            if tag == "script" and a.get("src"):
                self.links.append((a["src"], line, "script"))
        classes = (a.get("class") or "").split()
        if self._exempt is None and ("legal" in classes or "facts" in classes):
            self._exempt = len(self._in)
        if tag == "video":
            self._video = [line, bool(a.get("poster")), False]
            self.videos.append(self._video)
            if a.get("poster"):
                self.links.append((a["poster"], line, "img"))
        if tag == "track" and a.get("kind") == "captions" and a.get("srclang") == "en":
            if getattr(self, "_video", None):
                self._video[2] = True
        if tag in ("source", "track") and a.get("src"):
            self.links.append((a["src"], line, "img"))
        if tag == "a" and "href" in a:
            self.links.append((a["href"], line, "a"))
        if tag == "link" and a.get("rel") in ("icon", "apple-touch-icon", "stylesheet"):
            self.links.append((a.get("href", ""), line, "link"))
        if tag == "li" and "card" in (a.get("class") or "").split():
            self._card = len(self._in)
            if a.get("data-store") not in self.OFFERED:
                self.problems.append(f"line {line}: a card for a store the site doesn't offer: {a.get('data-store')!r}")
        if tag == "div" and "art" in (a.get("class") or "").split():
            self.covers.append([line, None])
            self._art = len(self._in)
        if tag == "img":
            if self._art is not None and self.covers[-1][1] is None:
                self.covers[-1][1] = a.get("src", "")
            if "alt" not in a:
                self.problems.append(f"line {line}: <img src={a.get('src')!r}> has no alt (use alt=\"\" if decorative)")
            self.links.append((a.get("src", ""), line, "img"))
        if tag == "label" and "for" in a:
            self.labels_for.add(a["for"])
        if tag == "input" and a.get("type") != "hidden":
            self.inputs.append((a, line))
        if tag == "button":
            if a.get("type") not in ("button", "submit", "reset"):
                self.problems.append(f"line {line}: <button> without an explicit type")
            self._button = [a, ""]
        if tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
            self.headings.append((int(tag[1]), line))
        for k, v in attrs:
            if v and "{" in v and k not in ("onerror", "onclick", "oninput", "style", "content"):
                self.problems.append(f"line {line}: template text in {tag}[{k}]: {v[:60]!r}")
        if tag not in self.VOID:
            self._in.append(tag)

    def handle_endtag(self, tag):
        if tag in ("script", "style"):
            self._raw -= 1
        if tag == "button" and self._button is not None:
            a, text = self._button
            if not text.strip() and not a.get("aria-label") and not a.get("aria-labelledby"):
                self.problems.append(f"line {self.getpos()[0]}: <button> with no accessible name")
            self._button = None
        if tag in self._in:
            while self._in and self._in.pop() != tag:
                pass
        if self._art is not None and len(self._in) <= self._art:
            self._art = None
        if self._card is not None and len(self._in) <= self._card:
            self._card = None
        if self._exempt is not None and len(self._in) <= self._exempt:
            self._exempt = None

    def handle_data(self, data):
        if self._raw:
            return
        if self._in and self._in[-1] == "title":
            self.title += data
        if self._button is not None:
            self._button[1] += data
        # Every game comes through a store (Kenneth, 2026-10-30): the site never offers or implies
        # a store-less or manual-download path.
        if re.search(r"\bno[- ]store\b|without (a|the|any) store\b|manual download", data, re.I):
            self.problems.append(f"line {self.getpos()[0]}: implies a store-less path: {data.strip()[:60]!r}")
        # Steam only for now (Kenneth, 2026-11-02): no hidden store in the site's own copy. A card's
        # facts are its profile's words (a Steam game's DRM may name another account), so they pass.
        if self._card is None:
            for name in self.HIDDEN:
                if re.search(rf"\b{re.escape(name)}\b", data, re.I):
                    self.problems.append(f"line {self.getpos()[0]}: names {name}, a store the site doesn't offer yet: {data.strip()[:60]!r}")
        if self.plain and self._exempt is None:
            m = JARGON.search(data)
            if m:
                self.problems.append(f"line {self.getpos()[0]}: says {m.group(0)!r} to a player (docs/DESIGN.md §2): {data.strip()[:60]!r}")
        if "{" in data or "}" in data:
            self.problems.append(f"line {self.getpos()[0]}: template text leaked into the page: {data.strip()[:60]!r}")


def luminance(hex_colour):
    h = hex_colour.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))

    def lin(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contrast(a, b):
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def check_external(urls):
    problems, notes = [], []
    for url in sorted(urls):
        req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "cellar-check-site"})
        status = None
        for _ in range(2):  # a retry, or the GET after a refused HEAD
            try:
                with urllib.request.urlopen(req, timeout=20) as r:
                    status = r.status
                break
            except urllib.error.HTTPError as e:
                status = e.code
                if e.code == 405 and req.get_method() == "HEAD":  # some hosts refuse HEAD
                    req = urllib.request.Request(url, headers={"User-Agent": "cellar-check-site"})
                    continue
                break
            except (urllib.error.URLError, OSError) as e:
                status = f"unreachable ({e})"
        if status in (404, 410):
            problems.append(f"{url}: {status}")
        elif not (isinstance(status, int) and status < 400):
            notes.append(f"{url}: {status} (not failed: says nothing about the link)")
    return problems, notes


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("site", nargs="?", default=os.path.join(ROOT, "pages", "dist"))
    ap.add_argument("--external", action="store_true", help="also check http(s) links")
    args = ap.parse_args()

    gen = load_generator()
    Page.OFFERED = tuple(gen.OFFERED)
    Page.HIDDEN = tuple(n for k, label in gen.STORES.items() if k not in gen.OFFERED
                        for n in {label, gen.OWNERS[k]})
    site = os.path.abspath(args.site)
    pages = sorted(glob.glob(os.path.join(site, "*.html")))
    if not pages:
        sys.exit(f"error: no pages in {site} — run pages/gen-site.py first")

    parsed, problems, external, covers = {}, [], set(), set()
    for path in pages:
        p = Page()
        p.plain = os.path.basename(path) in PLAIN_PAGES
        with open(path, encoding="utf-8") as f:
            p.feed(f.read())
        parsed[os.path.basename(path)] = p

    repo_main = gen.REPO + "/blob/main/"
    for name, p in parsed.items():
        where = name
        problems += [f"{where}: {x}" for x in p.problems]
        if not p.lang:
            problems.append(f"{where}: <html> has no lang")
        if not p.title.strip():
            problems.append(f"{where}: no <title>")
        h1 = [line for level, line in p.headings if level == 1]
        if len(h1) != 1:
            problems.append(f"{where}: {len(h1)} <h1> elements (expected exactly one)")
        prev = 0
        for level, line in p.headings:
            if prev and level > prev + 1:
                problems.append(f"{where}: line {line}: <h{level}> follows <h{prev}> (skipped a level)")
            prev = level
        seen = {}
        for ident, line in p.ids:
            if ident in seen:
                problems.append(f"{where}: line {line}: duplicate id {ident!r} (first on line {seen[ident]})")
            seen.setdefault(ident, line)
        for line, src in p.covers:
            if not src:
                problems.append(f"{where}: line {line}: a game card has no cover image")
            elif urllib.parse.urlsplit(src).scheme in ("http", "https"):
                covers.add(src)
        for line, poster, captions in p.videos:
            if not poster or not captions:
                problems.append(f"{where}: line {line}: <video> needs a poster and an English captions <track>")
        for a, line in p.inputs:
            if a.get("id") not in p.labels_for and not a.get("aria-label") and not a.get("aria-labelledby"):
                problems.append(f"{where}: line {line}: <input> has no label")

        for href, line, kind in p.links:
            if not href:
                problems.append(f"{where}: line {line}: empty link")
                continue
            u = urllib.parse.urlsplit(href)
            if u.scheme in ("mailto", "data"):
                continue
            if u.scheme in ("http", "https"):
                if href.startswith(repo_main):
                    rel = urllib.parse.unquote(href[len(repo_main):].split("#")[0])
                    if not os.path.exists(os.path.join(ROOT, rel)):
                        problems.append(f"{where}: line {line}: {href} — {rel} is not in this repository")
                elif kind == "a":
                    # Other remote images are covers, checked below from p.covers.
                    external.add(href.split("#")[0])
                continue
            # Relative, or rooted at the site's own path (404.html links that way).
            target_path = u.path
            if target_path.startswith(gen.SITE_PATH):
                target_path = target_path[len(gen.SITE_PATH):]
            elif target_path.startswith("/"):
                problems.append(f"{where}: line {line}: {href} is rooted outside {gen.SITE_PATH}")
                continue
            target = os.path.basename(target_path) if target_path else name
            if target_path and not os.path.exists(os.path.join(site, target_path)):
                problems.append(f"{where}: line {line}: {href} — no {target_path} in the site")
                continue
            if u.fragment and target.endswith(".html"):
                ids = {i for i, _l in parsed[target].ids} if target in parsed else set()
                if u.fragment not in ids:
                    problems.append(f"{where}: line {line}: {href} — no #{u.fragment} in {target}")

    for path in sorted(glob.glob(os.path.join(site, "media", "*"))):
        ext = os.path.splitext(path)[1].lower()
        size = os.path.getsize(path)
        if ext not in MEDIA_LIMITS:
            problems.append(f"media/{os.path.basename(path)}: not a {', '.join(sorted(MEDIA_LIMITS))} file")
        elif size > MEDIA_LIMITS[ext]:
            problems.append(f"media/{os.path.basename(path)}: {size:,} bytes, over the {MEDIA_LIMITS[ext]:,} limit")

    for what, fg, bg, minimum in gen.CONTRAST:
        ratio = contrast(fg, bg)
        if ratio < minimum:
            problems.append(f"contrast: {what}: {fg} on {bg} is {ratio:.2f}:1, needs {minimum}:1")

    notes = []
    if args.external:
        ext_problems, notes = check_external(external | covers)
        problems += ext_problems

    for note in notes:
        print(f"note: {note}")
    if problems:
        print(f"{len(problems)} problem(s) in {site}:", file=sys.stderr)
        for x in problems:
            print(f"  {x}", file=sys.stderr)
        sys.exit(1)
    checked = f", {len(external)} external links" if args.external else ""
    print(f"Site OK: {len(pages)} pages, {sum(len(p.links) for p in parsed.values())} links"
          f"{checked}, {len(gen.CONTRAST)} contrast pairs")


if __name__ == "__main__":
    main()
