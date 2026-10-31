#!/usr/bin/env python3
"""Check the generated site before it ships: links, structure, and the contrast of its palette.

Run after Scripts/gen-site.py:  python3 Scripts/check-site.py [--external] [site-dir]

Fails (exit 1) on:
  - a relative link, image or anchor that points at nothing in the site
  - a link into this repository's main branch (…/blob/main/<path>) whose file does not exist here
  - structure: not exactly one <h1>, a skipped heading level, an <img> without alt, a duplicate
    id, an <input> without a label, a <button> without a type or an accessible name, a missing
    lang or <title>, template text that leaked into the page ({…}), or copy implying a game
    can come from no store
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


def load_generator():
    spec = importlib.util.spec_from_file_location("gen_site", os.path.join(ROOT, "Scripts", "gen-site.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Page(html.parser.HTMLParser):
    VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids, self.links, self.headings, self.problems = [], [], [], []
        self.labels_for, self.inputs = set(), []
        self.lang = None
        self.title = ""
        self._in = []          # open element stack
        self._button = None    # [attrs, text] of the button being read
        self._raw = 0          # inside <script>/<style>
        self.covers = []       # [line, cover src or None] per game card's .art
        self._art = None       # stack depth of the .art being read

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
        if tag == "a" and "href" in a:
            self.links.append((a["href"], line, "a"))
        if tag == "link" and a.get("rel") in ("icon", "apple-touch-icon", "stylesheet"):
            self.links.append((a.get("href", ""), line, "link"))
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
        for attempt in (1, 2):
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
    ap.add_argument("site", nargs="?", default=os.path.join(ROOT, "site"))
    ap.add_argument("--external", action="store_true", help="also check http(s) links")
    args = ap.parse_args()

    gen = load_generator()
    site = os.path.abspath(args.site)
    pages = sorted(glob.glob(os.path.join(site, "*.html")))
    if not pages:
        sys.exit(f"error: no pages in {site} — run Scripts/gen-site.py first")

    parsed, problems, external, covers = {}, [], set(), set()
    for path in pages:
        p = Page()
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
