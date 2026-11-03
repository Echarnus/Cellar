#!/usr/bin/env python3
"""Generate the static Cellar site from profiles/*.toml into pages/dist/.

Pages: index.html (landing page + supported games), faq.html, 404.html, plus sitemap.xml and
robots.txt. Data-driven: every game card comes from a profile, so the page can't drift from what
Cellar supports, and the Download button names the real installer of the latest release.

Run: python3 pages/gen-site.py

Environment (all optional):
  CELLAR_SITE_OUT        write somewhere other than pages/dist/
  CELLAR_SITE_OFFLINE=1  skip the latest-release lookup (the button then opens the releases page)
  CELLAR_SITE_MEDIA      read the screenshots and video from somewhere other than pages/media/
  CELLAR_TOML_FALLBACK=1 use the hand-rolled TOML parser even where tomllib exists, so CI can prove
                         both parsers read every profile the same way
  GITHUB_TOKEN           sent with the release lookup, only to lift the anonymous rate limit
"""
import glob
import html
import json
import os
import re
import shutil
import sys
import urllib.error
import urllib.request


def _val(s):
    s = s.strip()
    if s and s[0] in "\"'":
        return s[1:].split(s[0], 1)[0]
    if s in ("true", "false"):
        return s == "true"
    try:
        return int(s)
    except ValueError:
        return s


def _parse_toml_fallback(path):
    """Scalars-only TOML, for Pythons without tomllib. See skills/profiles.md for what it can't read."""
    data, section = {}, None
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            m = re.match(r"\[([^\]]+)\]$", line)
            if m:
                section = {}
                data[m.group(1)] = section
                continue
            if "=" in line and section is not None:
                k, v = line.split("=", 1)
                section[k.strip()] = _val(v)
    return data


try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:
    tomllib = None


def parse_toml(path):
    if tomllib is None or os.environ.get("CELLAR_TOML_FALLBACK") == "1":
        return _parse_toml_fallback(path)
    with open(path, "rb") as f:
        return tomllib.load(f)


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.environ.get("CELLAR_SITE_OUT") or os.path.join(ROOT, "pages", "dist")
OWNER_REPO = "Echarnus/Cellar"
REPO = f"https://github.com/{OWNER_REPO}"
RELEASES = f"{REPO}/releases"
SITE_URL = "https://echarnus.github.io/Cellar/"
# Where the site lives on its host. Only 404.html needs it: GitHub Pages serves that page for any
# missing path, at any depth, so its links cannot be relative.
SITE_PATH = "/Cellar/"
MIN_MACOS = "27"  # LSMinimumSystemVersion in app/Scripts/package.sh and app/Package.swift

STORES = {  # profile store → how the site labels it
    "steam": "Steam",
    "battlenet": "Battle.net",
    "gog": "GOG",
}
# The stores the site talks about. Mirrors StoreAvailability.offered in the app
# (app/Packages/CellarDomain/Sources/CellarDomain/Store/StoreAvailability.swift): the first release
# is Steam only (#221), so Battle.net and GOG games, copy and questions are left out — not deleted.
# To bring a store back, add it here; every store-specific sentence below is written through
# only()/stores_phrase() so it returns with it.
OFFERED = ("steam",)
OWNERS = {"steam": "Valve", "battlenet": "Blizzard", "gog": "GOG"}  # for the affiliation line


def only(store, text):
    """`text` when `store` is offered on the site, otherwise nothing."""
    return text if store in OFFERED else ""


def stores_phrase(last="and"):
    """The offered stores as prose: "Steam", "Steam and GOG", "Steam, Battle.net and GOG"."""
    names = [STORES[k] for k in OFFERED]
    return names[0] if len(names) == 1 else f"{', '.join(names[:-1])} {last} {names[-1]}"


def your_stores(plural, singular):
    return plural if len(OFFERED) > 1 else singular

STATUS = {  # profile status → (label, css class, what it means)
    "playable": ("Playable", "ok", "Someone played it on a Mac named in its technical details."),
    "experimental": ("Experimental", "warn", "It runs, with caveats worth reading first."),
    "untested": ("Untested", "muted", "Cellar knows how to set it up; nobody has confirmed it plays yet."),
}

# Profile DRM slugs that read badly as-is. Anything else is shown exactly as the profile says it.
DRM_LABELS = {"denuvo-anti-tamper": "Denuvo Anti-Tamper"}

# ---------------------------------------------------------------------------------------------
# Palette. One table, two uses: the CSS custom properties below are written from it, and
# pages/check-site.py measures CONTRAST against it, so a colour change that drops a pair under
# WCAG 2.2 AA fails CI instead of shipping. Chip backgrounds are solid, not alpha, so the ratio
# that is measured is the ratio that is drawn.
# ---------------------------------------------------------------------------------------------
LIGHT = {
    "bg": "#fbf8f7", "surface": "#ffffff", "surface-2": "#f3eded", "fg": "#1c1a1d",
    "muted": "#5f5960", "line": "#e4d9da", "link": "#9b2546", "focus": "#9b2546",
    "primary": "#8e1f3d", "on-primary": "#ffffff",
    "ok": "#1f7a3d", "warn": "#9a5a00", "untested": "#5f5960",
    "steam": "#1f6fae", "steam-bg": "#e8f1f9",
    "battlenet": "#006c9e", "battlenet-bg": "#e3f3fa",
    "gog": "#7a32ab", "gog-bg": "#f3eaf9",
    "shadow": "rgba(40,16,24,.10)",
}
DARK = {
    "bg": "#121014", "surface": "#1c181c", "surface-2": "#262026", "fg": "#f4eff1",
    "muted": "#b0a8ae", "line": "#352c32", "link": "#f59ab5", "focus": "#f59ab5",
    "primary": "#b02e57", "on-primary": "#ffffff",
    "ok": "#6ad48a", "warn": "#f2b25c", "untested": "#b0a8ae",
    "steam": "#7ab8e8", "steam-bg": "#1a2834",
    "battlenet": "#4cc4ff", "battlenet-bg": "#142a35",
    "gog": "#cf97ee", "gog-bg": "#2a1f33",
    "shadow": "rgba(0,0,0,.45)",
}
# The hero band is the brand colour in both appearances, with white type on it.
HERO = ("#a52a52", "#8e1f3d", "#4a0f22")
# The launch section is the page's one dark moment, the same in both appearances.
DEEP = {"deep": "#1c0b12", "deep-2": "#26111a", "deep-muted": "#cdb9c1"}
# Status badges sit on cover art, so they carry their own solid colours in both appearances.
BADGES = {"ok": "#1f7a3d", "warn": "#9a5a00", "muted": "#5f5960"}

# (what, foreground, background, minimum ratio). Text is 4.5:1; focus rings and borders that
# identify a control are 3:1 (WCAG 2.2 SC 1.4.3 and 1.4.11).
CONTRAST = []
for _theme, _p in (("light", LIGHT), ("dark", DARK)):
    for _bg in ("bg", "surface", "surface-2"):
        CONTRAST += [(f"{_theme}: text on {_bg}", _p["fg"], _p[_bg], 4.5),
                     (f"{_theme}: secondary text on {_bg}", _p["muted"], _p[_bg], 4.5),
                     (f"{_theme}: link on {_bg}", _p["link"], _p[_bg], 4.5),
                     (f"{_theme}: focus ring on {_bg}", _p["focus"], _p[_bg], 3.0)]
    for _k in ("ok", "warn", "untested"):
        CONTRAST.append((f"{_theme}: {_k} status on surface", _p[_k], _p["surface"], 4.5))
    for _k in STORES:
        CONTRAST.append((f"{_theme}: {_k} chip", _p[_k], _p[f"{_k}-bg"], 4.5))
    CONTRAST.append((f"{_theme}: primary button", _p["on-primary"], _p["primary"], 4.5))
for _k in ("deep", "deep-2"):
    CONTRAST += [(f"white text on {_k}", "#ffffff", DEEP[_k], 4.5),
                 (f"secondary text on {_k}", DEEP["deep-muted"], DEEP[_k], 4.5)]
for _stop in HERO:
    CONTRAST.append((f"hero text on {_stop}", "#ffffff", _stop, 4.5))
for _k, _c in BADGES.items():
    CONTRAST.append((f"{_k} badge", "#ffffff", _c, 4.5))


def _tokens(p):
    return "".join(f"--{k}:{v};" for k, v in p.items())


# Light is the base; dark applies when the system asks for it unless the visitor picked light, or
# whenever they picked dark. The toggle writes data-theme on <html>.
THEME_CSS = (f":root{{color-scheme:light dark;{_tokens(LIGHT)}}}\n"
             f"@media (prefers-color-scheme:dark){{:root:not([data-theme=light]){{{_tokens(DARK)}}}}}\n"
             f":root[data-theme=dark]{{{_tokens(DARK)}}}\n"
             f":root[data-theme=light]{{color-scheme:light}}:root[data-theme=dark]{{color-scheme:dark}}\n"
             f":root{{--hero-1:{HERO[0]};--hero-2:{HERO[1]};--hero-3:{HERO[2]};"
             + "".join(f"--badge-{k}:{v};" for k, v in BADGES.items()) + _tokens(DEEP) + "}\n")

# One stylesheet for every page, inlined — no build step, no extra request. A plain string (single
# braces), interpolated into the page f-strings.
CSS = THEME_CSS + """
/* Type follows the system: SF Pro on Apple devices, at Apple's own sizes (body 17/1.47). Wine is
   the accent, not the wallpaper: the primary button, links, the icon and one glow. Sections are
   separated by space, not by boxes; hairlines only inside lists. */
*{box-sizing:border-box}
html{scroll-behavior:smooth;-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--fg);
  font:17px/1.47 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Roboto,"Helvetica Neue",sans-serif;
  letter-spacing:-.022em;-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}
img,svg{max-width:100%}
a{color:var(--link);text-underline-offset:.18em;text-decoration:none}
a:hover{text-decoration:underline}
:focus-visible{outline:3px solid var(--focus);outline-offset:3px;border-radius:8px}
h1,h2,h3{line-height:1.1;letter-spacing:-.015em;margin:0;font-weight:700}
p{margin:0 0 1em}
code{font:.86em/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--surface-2);
  padding:2px 6px;border-radius:6px;overflow-wrap:anywhere;letter-spacing:0}
.wrap{max-width:1068px;margin:0 auto;padding:0 22px}
.narrow{max-width:760px;margin-left:auto;margin-right:auto}
.center{text-align:center}
.sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
.skip{position:absolute;left:12px;top:-60px;z-index:20;background:var(--surface);color:var(--fg);
  padding:12px 18px;border-radius:10px;border:1px solid var(--line);font-weight:600}
.skip:focus{top:12px}

/* Top bar: translucent, 52px, small type, like the menu of any Apple page */
.top{position:sticky;top:0;z-index:10;background:color-mix(in srgb,var(--bg) 80%,transparent);
  -webkit-backdrop-filter:saturate(180%) blur(20px);backdrop-filter:saturate(180%) blur(20px);
  border-bottom:1px solid color-mix(in srgb,var(--line) 70%,transparent)}
@supports not (background:color-mix(in srgb,red 50%,blue)){.top{background:var(--bg);border-bottom-color:var(--line)}}
.top .wrap{display:flex;align-items:center;gap:6px;min-height:52px;flex-wrap:wrap}
.brand{display:inline-flex;align-items:center;gap:9px;color:var(--fg);text-decoration:none;
  font-weight:600;font-size:1.05rem;margin-right:auto;min-height:44px}
.brand:hover{text-decoration:none}
.brand img{width:28px;height:28px}
.nav{display:flex;gap:0;order:3;width:100%;overflow-x:auto;margin:0 -10px;padding:0 0 4px;scrollbar-width:none}
.nav::-webkit-scrollbar{display:none}
.nav a{color:var(--muted);text-decoration:none;padding:0 10px;font-size:.82rem;letter-spacing:-.01em;
  min-height:44px;display:inline-flex;align-items:center;white-space:nowrap}
.nav a:hover{color:var(--fg)}
.nav a[aria-current=page]{color:var(--fg)}
@media (min-width:760px){.nav{order:0;width:auto;margin:0 8px 0 0;padding:0;overflow:visible}}
.icon-btn{display:inline-grid;place-items:center;width:44px;height:44px;border-radius:50%;
  border:0;background:transparent;color:var(--muted);cursor:pointer}
.icon-btn:hover{color:var(--fg);background:var(--surface-2)}
.icon-btn svg{width:18px;height:18px}
.icon-btn .moon{display:none}
:root[data-theme=dark] .icon-btn .sun{display:none}
:root[data-theme=dark] .icon-btn .moon{display:block}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]) .icon-btn .sun{display:none}
  :root:not([data-theme=light]) .icon-btn .moon{display:block}}
.no-js .icon-btn{display:none}

/* Buttons: one filled pill for the one action; everything else is a text link with a chevron */
.btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;min-height:44px;
  padding:10px 22px;border-radius:980px;font-weight:500;text-decoration:none;border:1px solid transparent;
  transition:background-color .15s ease,color .15s ease,border-color .15s ease;cursor:pointer}
.btn:hover{text-decoration:none}
.btn svg{width:17px;height:17px;flex:none}
.btn-primary{background:var(--primary);color:var(--on-primary)}
.btn-primary:hover{background:color-mix(in srgb,var(--primary) 88%,#000)}
.btn-small{padding:4px 14px;min-height:32px;font-size:.8rem;margin:6px 0}
.btn-big{padding:13px 28px;font-size:1.06rem}
.btn-ghost{color:var(--fg);border-color:var(--line);background:transparent}
.btn-ghost:hover{border-color:var(--muted)}
.btn-ghost-dark{color:var(--link);border-color:var(--link);background:transparent}
.btn-ghost-dark:hover{background:var(--link);color:var(--bg)}
.chev{display:inline-flex;align-items:center;min-height:44px;font-size:1.06rem}
.chev::after{content:"";display:inline-block;width:.42em;height:.42em;margin-left:.42em;
  border-right:1.6px solid currentColor;border-top:1.6px solid currentColor;transform:rotate(45deg)}
.fine{color:var(--muted);font-size:.82rem;line-height:1.45;letter-spacing:-.01em}

/* Hero: plain page, centred; the picture carries it */
.hero{text-align:center;padding:72px 0 0;overflow:hidden}
.hero .appicon{width:96px;height:96px;margin:0 auto 18px;display:block}
.hero h1{font-size:clamp(2.6rem,7vw,4.6rem);line-height:1.05;max-width:15ch;margin:0 auto}
.hero .lede{font-size:clamp(1.15rem,2.2vw,1.45rem);line-height:1.38;color:var(--muted);max-width:34ch;
  margin:22px auto 30px;letter-spacing:-.01em}
.hero .ctas{display:flex;gap:10px 28px;flex-wrap:wrap;align-items:center;justify-content:center}
.hero .fine{margin:22px auto 0;max-width:60ch}
.hero .fine.sum{margin-top:6px}
.stage{position:relative;margin:56px auto 0;max-width:980px}
.stage::before{content:"";position:absolute;inset:8% 4% -6%;z-index:-1;border-radius:50%;
  background:radial-gradient(closest-side,color-mix(in srgb,var(--primary) 30%,transparent),transparent);filter:blur(30px)}
.page-head{padding:64px 0 8px}
.page-head h1{font-size:clamp(2.4rem,6vw,3.6rem)}
.page-head p{margin:16px 0 0;max-width:58ch;font-size:1.2rem;line-height:1.4;color:var(--muted)}

/* A Mac window: frames a screenshot, or stands in for one until it is captured */
.window{border-radius:12px;overflow:hidden;background:var(--surface);
  box-shadow:0 0 0 1px var(--line),0 30px 70px -28px var(--shadow)}
.window .bar{height:30px;display:flex;align-items:center;gap:8px;padding:0 12px;background:var(--surface-2);
  border-bottom:1px solid var(--line)}
.window .bar i{width:12px;height:12px;border-radius:50%;background:var(--line)}
.window img,.window video{display:block;width:100%;height:auto}
.soon{aspect-ratio:16/10;display:grid;place-items:center;align-content:center;gap:8px;padding:24px;text-align:center;
  color:var(--muted);background:radial-gradient(70% 60% at 50% 45%,color-mix(in srgb,var(--primary) 9%,var(--surface)),var(--surface))}
.soon b{color:var(--fg);font-weight:600;font-size:1.05rem}
.soon .tag{font-size:.75rem;font-weight:600;letter-spacing:.02em;color:var(--link);
  border:1px solid currentColor;border-radius:980px;padding:2px 10px}
.soon span{max-width:40ch;font-size:.92rem}

/* Sections */
section.block{padding:120px 0 0}
@media (max-width:700px){section.block{padding-top:80px}}
.section-head{max-width:760px;margin:0 0 48px}
.section-head.center{margin-left:auto;margin-right:auto}
.section-head h2,.big{font-size:clamp(2rem,5vw,3.25rem);line-height:1.08}
.section-head p{color:var(--muted);font-size:clamp(1.08rem,1.8vw,1.3rem);line-height:1.4;margin:18px 0 0}
.section-head.center p{margin-left:auto;margin-right:auto;max-width:44ch}

/* Feature rows: text on one side, the picture on the other, alternating */
.rows{list-style:none;margin:0;padding:0;display:grid;gap:96px}
.row{display:grid;gap:28px;align-items:center}
@media (min-width:900px){.row{grid-template-columns:5fr 7fr;gap:64px}
  .row:nth-child(even){grid-template-columns:7fr 5fr}.row:nth-child(even) .copy{order:2}}
.row h3{font-size:clamp(1.6rem,3vw,2rem);line-height:1.14;margin-bottom:14px}
.row p{color:var(--muted);font-size:1.06rem;margin:0}
.row p b{color:var(--fg);font-weight:600}
.row figure{margin:0}
.row figcaption{color:var(--muted);font-size:.85rem;margin-top:12px}

/* Launch: the one dark moment on the page, in both appearances */
.launch{margin-top:120px;padding:104px 0;background:var(--deep);color:#fff}
@media (max-width:700px){.launch{margin-top:80px;padding:72px 0}}
.launch .section-head p{color:var(--deep-muted)}
.launch a{color:#fff;text-decoration:underline}
.launch-grid{display:grid;gap:40px;align-items:center}
@media (min-width:900px){.launch-grid{grid-template-columns:5fr 7fr;gap:64px}}
.launch-grid .section-head{margin:0}
.launch .window{background:var(--deep-2);box-shadow:0 0 0 1px rgba(255,255,255,.1),0 40px 80px -30px #000}
.launch .window .bar{background:rgba(255,255,255,.06);border-color:rgba(255,255,255,.08)}
.launch .window .bar i{background:rgba(255,255,255,.18)}
.launch figcaption{color:var(--deep-muted);font-size:.85rem;margin-top:12px}
.stages{list-style:none;margin:0;padding:28px 28px 22px;display:grid;gap:4px}
.stages li{display:grid;grid-template-columns:22px 1fr;gap:14px;align-items:start;padding:10px 0;
  border-bottom:1px solid rgba(255,255,255,.08);color:var(--deep-muted)}
.stages li:last-child{border-bottom:0}
.stages b{display:block;color:#fff;font-weight:600}
.stages small{font-size:.86rem;line-height:1.4}
.stages .dot{width:18px;height:18px;margin-top:3px;border-radius:50%;border:1.6px solid rgba(255,255,255,.35);position:relative}
.stages .dot::after{content:"";position:absolute;left:5px;top:2px;width:4px;height:8px;border:solid;
  border-width:0 1.6px 1.6px 0;transform:rotate(45deg)}
/* Each stage ticks in turn on a 12-second loop; with reduced motion they all show done. */
.stages .dot{color:transparent;animation:12s infinite}
.stages .dot::after{border-color:currentColor;opacity:1}
@keyframes s1{0%,4%{background:transparent;border-color:rgba(255,255,255,.35);color:transparent}6%,90%{background:var(--primary);border-color:var(--primary);color:#fff}94%,100%{background:transparent;border-color:rgba(255,255,255,.35);color:transparent}}
@keyframes s2{0%,18%{background:transparent;border-color:rgba(255,255,255,.35);color:transparent}20%,90%{background:var(--primary);border-color:var(--primary);color:#fff}94%,100%{background:transparent;border-color:rgba(255,255,255,.35);color:transparent}}
@keyframes s3{0%,32%{background:transparent;border-color:rgba(255,255,255,.35);color:transparent}34%,90%{background:var(--primary);border-color:var(--primary);color:#fff}94%,100%{background:transparent;border-color:rgba(255,255,255,.35);color:transparent}}
@keyframes s4{0%,46%{background:transparent;border-color:rgba(255,255,255,.35);color:transparent}48%,90%{background:var(--primary);border-color:var(--primary);color:#fff}94%,100%{background:transparent;border-color:rgba(255,255,255,.35);color:transparent}}
@keyframes s5{0%,60%{background:transparent;border-color:rgba(255,255,255,.35);color:transparent}62%,90%{background:var(--primary);border-color:var(--primary);color:#fff}94%,100%{background:transparent;border-color:rgba(255,255,255,.35);color:transparent}}
.stages li:nth-child(1) .dot{animation-name:s1}.stages li:nth-child(2) .dot{animation-name:s2}.stages li:nth-child(3) .dot{animation-name:s3}.stages li:nth-child(4) .dot{animation-name:s4}.stages li:nth-child(5) .dot{animation-name:s5}
.stages-tag{display:inline-block;margin:0 28px 22px;font-size:.75rem;font-weight:600;color:#fff;
  border:1px solid rgba(255,255,255,.4);border-radius:980px;padding:2px 10px}

/* "Everything else": a spec grid, no boxes */
.specs{list-style:none;margin:0;padding:0;display:grid;gap:0 40px;grid-template-columns:repeat(auto-fill,minmax(min(100%,300px),1fr))}
.specs li{padding:22px 0 24px;border-top:1px solid var(--line)}
.specs svg{width:26px;height:26px;color:var(--link);margin-bottom:12px;display:block}
.specs h3{font-size:1.1rem;line-height:1.25;margin-bottom:6px;font-weight:600}
.specs p{color:var(--muted);margin:0;font-size:.98rem}

/* Free: one statement on a quiet field */
.free{margin-top:120px;padding:104px 0;background:var(--surface-2)}
@media (max-width:700px){.free{margin-top:80px;padding:72px 0}}
.free .section-head{margin-bottom:56px}
.three{list-style:none;margin:0;padding:0;display:grid;gap:32px 48px;grid-template-columns:repeat(auto-fit,minmax(min(100%,240px),1fr))}
.three h3{font-size:1.2rem;margin-bottom:8px;font-weight:600}
.three p{color:var(--muted);margin:0}
.sponsor{margin:64px auto 0;max-width:640px;text-align:center;padding-top:40px;border-top:1px solid var(--line)}
.sponsor p{color:var(--muted);margin:0 0 18px}
.sponsor .pending{display:inline-flex;align-items:center;gap:8px;min-height:44px;padding:10px 22px;border-radius:980px;
  border:1px dashed var(--muted);color:var(--muted);font-weight:500}
.sponsor .pending svg{width:17px;height:17px}

/* Getting started: big quiet numerals, no circles */
.steps{list-style:none;margin:0;padding:0;display:grid;gap:40px 48px;counter-reset:step;
  grid-template-columns:repeat(auto-fit,minmax(min(100%,260px),1fr))}
.steps li{counter-increment:step}
.steps li::before{content:counter(step);display:block;font-size:3.4rem;font-weight:200;line-height:1;color:var(--muted);margin-bottom:16px;letter-spacing:-.03em}
.steps h3{font-size:1.25rem;margin-bottom:8px;font-weight:600}
.steps p{margin:0;color:var(--muted)}

/* Games */
.toolbar{display:flex;flex-wrap:wrap;gap:12px 16px;align-items:center;margin:0 0 20px}
.no-js .toolbar{display:none}
.search{position:relative;flex:1 1 240px;max-width:340px}
.search svg{position:absolute;left:12px;top:50%;width:17px;height:17px;transform:translateY(-50%);color:var(--muted);pointer-events:none}
.search input{width:100%;min-height:44px;padding:10px 14px 10px 38px;border-radius:10px;border:1px solid var(--muted);
  background:var(--surface);color:var(--fg);font:inherit;font-size:1rem}
.seg{display:inline-flex;flex-wrap:wrap;gap:2px;padding:2px;border-radius:9px;background:var(--surface-2)}
.seg button{min-height:40px;padding:6px 14px;border:0;border-radius:7px;background:transparent;color:var(--fg);
  font:inherit;font-size:.9rem;cursor:pointer}
.seg button:hover{background:color-mix(in srgb,var(--surface) 60%,transparent)}
.seg button[aria-pressed=true]{background:var(--surface);font-weight:600;box-shadow:0 1px 3px var(--shadow)}
.seg .n{color:var(--muted);font-weight:400;margin-left:5px}
.count{color:var(--muted);font-size:.9rem;margin:0 0 18px}
.grid{display:grid;gap:36px 24px;grid-template-columns:repeat(auto-fill,minmax(min(100%,176px),1fr));list-style:none;margin:0;padding:0}
.card{display:flex;flex-direction:column}
.card[hidden]{display:none}
.card .art{position:relative;aspect-ratio:2/3;border-radius:12px;overflow:hidden;background:var(--surface-2);color:var(--muted);
  box-shadow:0 0 0 1px var(--line),0 14px 30px -18px var(--shadow);transition:transform .25s ease}
.card:hover .art{transform:scale(1.02)}
.card .art .ph{position:absolute;inset:0;display:grid;place-items:center;padding:16px;text-align:center;font-weight:600;font-size:1.05rem;line-height:1.25}
.card .art img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;display:block}
.card .art img.broken{display:none}
.badge{position:absolute;top:8px;left:8px;display:inline-flex;align-items:center;gap:5px;color:#fff;font-size:.72rem;
  font-weight:600;padding:3px 9px 3px 7px;border-radius:980px;background:var(--badge-muted);letter-spacing:0}
.badge svg{width:13px;height:13px}
.badge.ok{background:var(--badge-ok)}.badge.warn{background:var(--badge-warn)}
.card .meta{padding:14px 2px 0;display:flex;flex-direction:column;gap:8px;flex:1}
@media (max-width:540px){.card{flex-direction:row;gap:14px}.card .art{width:96px;flex:none;aspect-ratio:auto;min-height:144px}
  .card .art .ph{font-size:.8rem;padding:8px}.badge{top:5px;left:5px;font-size:.66rem;padding:2px 6px 2px 4px}
  .card .meta{padding:0}}
.card h3{font-size:1rem;line-height:1.25;font-weight:600}
.chip{display:inline-block;font-size:.76rem;font-weight:600;padding:2px 9px;border-radius:6px}
.chip.steam{color:var(--steam);background:var(--steam-bg)}
.chip.battlenet{color:var(--battlenet);background:var(--battlenet-bg)}
.chip.gog{color:var(--gog);background:var(--gog-bg)}
.facts{margin:0;display:grid;grid-template-columns:auto 1fr;gap:3px 10px;font-size:.8rem;line-height:1.4}
.facts dt{color:var(--muted)}
.facts dd{margin:0;overflow-wrap:anywhere}
.card .more{margin-top:auto;font-size:.8rem;min-height:44px;display:inline-flex;align-items:center}
.no-js .grid[data-cap]>.card:nth-child(n+11){display:none}
.more-games{text-align:center;margin:40px 0 0}
.games-page{padding-top:32px}
.empty{text-align:center;color:var(--muted);padding:40px 0}
.legend{display:grid;gap:12px 32px;grid-template-columns:repeat(auto-fit,minmax(min(100%,250px),1fr));margin:48px 0 0;padding:24px 0 0;
  list-style:none;border-top:1px solid var(--line)}
.legend li{display:flex;gap:10px;align-items:flex-start;color:var(--muted);font-size:.88rem}
.legend b{color:var(--fg);font-weight:600}
.legend svg{width:17px;height:17px;flex:none;margin-top:2px}
.legend .ok{color:var(--ok)}.legend .warn{color:var(--warn)}.legend .muted{color:var(--untested)}
.callout{margin:40px 0 0;padding:24px 0 0;border-top:1px solid var(--line)}
.callout h3{font-size:1.1rem;margin-bottom:6px;font-weight:600}
.callout p{margin:0;color:var(--muted)}

/* Requirements: a tech-specs table */
.reqs{margin:0;border-top:1px solid var(--line)}
.reqs div{display:grid;gap:4px 32px;padding:20px 0;border-bottom:1px solid var(--line)}
@media (min-width:700px){.reqs div{grid-template-columns:220px 1fr}}
.reqs dt{font-weight:600}
.reqs dd{margin:0;color:var(--muted)}

/* FAQ: rows divided by hairlines */
.qa-list{max-width:820px}
details.qa{border-bottom:1px solid var(--line);scroll-margin-top:72px}
details.qa:first-of-type{border-top:1px solid var(--line)}
details.qa>summary{cursor:pointer;list-style:none;padding:18px 2px;font-weight:600;display:flex;gap:14px;align-items:center;min-height:56px;font-size:1.06rem}
details.qa>summary::-webkit-details-marker{display:none}
details.qa>summary::after{content:"";flex:none;margin-left:auto;width:8px;height:8px;border-right:1.6px solid var(--muted);border-bottom:1.6px solid var(--muted);
  transform:rotate(45deg) translate(-2px,-2px);transition:transform .2s ease}
details.qa[open]>summary::after{transform:rotate(225deg) translate(-2px,-2px)}
details.qa .a{padding:0 2px 10px;color:var(--fg)}
details.qa .a p,details.qa .a ul,details.qa .a ol{margin:0 0 14px}
details.qa .a ul,details.qa .a ol{padding-left:20px}
details.qa .a pre{margin:0 0 14px;overflow-x:auto}
details.qa .a li{margin:5px 0}
.faq-layout{display:grid;gap:36px;padding:48px 0 0}
@media (min-width:960px){.faq-layout{grid-template-columns:220px 1fr}}
.toc{align-self:start}
@media (min-width:960px){.toc{position:sticky;top:76px}}
.toc h2{font-size:.8rem;color:var(--muted);margin:0 0 8px;font-weight:600}
.toc ol{list-style:none;margin:0;padding:0;display:flex;flex-wrap:wrap;gap:4px}
@media (min-width:960px){.toc ol{flex-direction:column}}
.toc a{display:inline-flex;align-items:center;min-height:40px;padding:0 12px;border-radius:8px;color:var(--fg);text-decoration:none;
  background:var(--surface-2);font-size:.92rem}
@media (min-width:960px){.toc a{background:none;display:flex;padding:0 10px}}
.toc a:hover{background:var(--surface-2);text-decoration:none}
.faq-section{margin:0 0 56px;scroll-margin-top:72px}
.faq-section h2{font-size:1.7rem;margin-bottom:6px}
.faq-section .lede{color:var(--muted);margin:0 0 16px}
.more-link{margin-top:20px}

/* Closing call + footer */
.band{margin:120px 0 0;padding:96px 0 104px;text-align:center;border-top:1px solid var(--line)}
@media (max-width:700px){.band{margin-top:80px;padding:72px 0}}
.band img{width:88px;height:88px;display:block;margin:0 auto 20px}
.band h2{font-size:clamp(2rem,5vw,3rem)}
.band p{margin:14px auto 28px;color:var(--muted);max-width:44ch;font-size:1.15rem}
.band .fine{margin:16px 0 0}
footer.site{background:var(--surface-2);padding:40px 0 48px;color:var(--muted);font-size:.8rem;line-height:1.5}
footer.site .cols{display:grid;gap:24px;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));margin-bottom:28px;
  padding-bottom:24px;border-bottom:1px solid var(--line)}
footer.site h2{font-size:.8rem;color:var(--fg);margin:0 0 6px;font-weight:600;letter-spacing:-.01em}
footer.site ul{list-style:none;margin:0;padding:0}
footer.site li a{display:inline-flex;align-items:center;min-height:32px;color:var(--muted)}
footer.site li a:hover{color:var(--fg)}
footer.site .legal{max-width:90ch;margin:0 0 10px}
footer.site .legal a{color:var(--fg)}
.notfound{padding:120px 22px 80px;text-align:center}
.notfound h1{font-size:clamp(2.2rem,5vw,3.2rem);margin-bottom:14px}
.notfound p{color:var(--muted);font-size:1.15rem}
.notfound .ctas{display:flex;gap:12px;justify-content:center;flex-wrap:wrap;margin-top:28px}

@media (prefers-reduced-motion:reduce){html{scroll-behavior:auto}*,*::before,*::after{animation:none!important;transition:none!important}
  .card:hover .art{transform:none}
  .stages .dot{background:var(--primary);border-color:var(--primary);color:#fff}}
@media (prefers-contrast:more){:root{--line:var(--muted)}.seg button[aria-pressed=true]{outline:2px solid var(--fg)}}
@media print{.top,.toolbar,.band,.launch{display:none}body{background:#fff;color:#000}}
"""

# Runs before first paint, so a visitor who chose a theme never sees the other one flash. Storage
# can be unavailable (private windows, blocked site data): every access is guarded.
HEAD_JS = ("<script>document.documentElement.classList.remove('no-js');"
           "try{var t=localStorage.getItem('cellar-theme');if(t==='light'||t==='dark')"
           "document.documentElement.dataset.theme=t}catch(e){}</script>")

THEME_JS = """
(function(){
  var root=document.documentElement, btn=document.getElementById('theme');
  if(!btn) return;
  var mq=window.matchMedia('(prefers-color-scheme: dark)');
  function dark(){return root.dataset.theme? root.dataset.theme==='dark' : mq.matches;}
  function sync(){var d=dark();btn.setAttribute('aria-pressed',String(d));
    btn.setAttribute('aria-label',d?'Dark mode is on. Switch to light mode':'Dark mode is off. Switch to dark mode');}
  btn.addEventListener('click',function(){
    var next=dark()?'light':'dark'; root.dataset.theme=next;
    try{localStorage.setItem('cellar-theme',next)}catch(e){}
    sync();});
  if(mq.addEventListener) mq.addEventListener('change',sync);
  sync();
})();
"""

GAMES_JS = """
(function(){
  var cards=[].slice.call(document.querySelectorAll('#grid .card'));
  var q=document.getElementById('q'), count=document.getElementById('count'), empty=document.getElementById('empty');
  var state={store:'all',status:'all'};
  var grid=document.getElementById('grid'), cap=parseInt(grid.dataset.cap||'0',10), more=document.getElementById('more');
  var params=new URLSearchParams(location.search);
  if(!cap){ q.value=params.get('q')||'';
    ['store','status'].forEach(function(k){var v=params.get(k); if(!v) return;
      var g=document.querySelector('.seg[data-key="'+k+'"]'); if(!g||!g.querySelector('[data-value="'+v+'"]')) return;
      state[k]=v; [].forEach.call(g.querySelectorAll('button'),function(x){x.setAttribute('aria-pressed',String(x.dataset.value===v));});});}
  function apply(){
    var term=(q.value||'').trim().toLowerCase(), matched=0, shown=0;
    cards.forEach(function(c){
      var ok=(!term||c.dataset.name.indexOf(term)>=0)
        &&(state.store==='all'||c.dataset.store===state.store)
        &&(state.status==='all'||c.dataset.status===state.status);
      if(ok) matched++;
      var show=ok&&(!cap||matched<=cap);
      c.hidden=!show; if(show) shown++;});
    var all=!term&&state.store==='all'&&state.status==='all';
    count.textContent=shown===cards.length? 'Showing all '+cards.length+' games'
      : all||shown===matched? 'Showing '+shown+' of '+cards.length+' games'
      : 'Showing '+shown+' of '+matched+' matching games';
    if(more){
      var p=new URLSearchParams(); if(term) p.set('q',q.value.trim());
      if(state.store!=='all') p.set('store',state.store); if(state.status!=='all') p.set('status',state.status);
      more.href='games.html'+(p.toString()?'?'+p.toString():'');
      more.hidden=matched<=cap;
      more.textContent=all? 'Show all '+cards.length+' games' : 'Show all '+matched+' matching games';}
    empty.hidden=matched>0;}
  [].forEach.call(document.querySelectorAll('.seg'),function(group){
    group.addEventListener('click',function(e){
      var b=e.target.closest('button'); if(!b) return;
      [].forEach.call(group.querySelectorAll('button'),function(x){x.setAttribute('aria-pressed',String(x===b));});
      state[group.dataset.key]=b.dataset.value; apply();});});
  q.addEventListener('input',apply);
  var reset=document.getElementById('reset');
  if(reset) reset.addEventListener('click',function(){
    q.value=''; state={store:'all',status:'all'};
    [].forEach.call(document.querySelectorAll('.seg button'),function(x){x.setAttribute('aria-pressed',String(x.dataset.value==='all'));});
    apply(); q.focus();});
  apply();
})();
"""

# Inline icons: 24×24, stroked in currentColor, always decorative (the text beside them says it).
_SVG = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" '
        'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">{}</svg>')
ICONS = {
    "download": '<path d="M12 4v11"/><path d="m7 10 5 5 5-5"/><path d="M5 20h14"/>',
    "play": '<circle cx="12" cy="12" r="9"/><path d="m10 8.5 5.5 3.5-5.5 3.5z"/>',
    "stores": '<path d="M4 9h16l-1.2 10.2a1 1 0 0 1-1 .8H6.2a1 1 0 0 1-1-.8z"/><path d="M8.5 9V7a3.5 3.5 0 0 1 7 0v2"/>',
    "chip": '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
    "profile": '<path d="M7 3h7l5 5v12a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z"/><path d="M14 3v5h5"/><path d="M9 13h6M9 17h4"/>',
    "gauge": '<path d="M4.5 17a8.5 8.5 0 1 1 15 0"/><path d="m12 13 4-4"/><circle cx="12" cy="13" r="1.3"/>',
    "shield": '<path d="M12 3 5 6v5c0 4.5 3 8.3 7 10 4-1.7 7-5.5 7-10V6z"/><path d="m9 12 2 2 4-4"/>',
    "window": '<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M3 8.5h18"/><path d="M14 12.5h4v4"/><path d="M10 16.5H6v-4"/>',
    "controller": '<path d="M7 7h10a4 4 0 0 1 3.9 3.1l1 4.6a2.6 2.6 0 0 1-4.6 2.1L15.5 15h-7l-1.8 1.8a2.6 2.6 0 0 1-4.6-2.1l1-4.6A4 4 0 0 1 7 7z"/><path d="M8 10v3M6.5 11.5h3"/><path d="M15.5 11h.01M17.5 12.5h.01"/>',
    "dock": '<rect x="3" y="15" width="18" height="5" rx="2"/><rect x="6" y="9" width="5" height="5" rx="1.2"/><rect x="13" y="9" width="5" height="5" rx="1.2"/><path d="M8.5 6V4.5"/>',
    "dlc": '<path d="M12 3 4 7v10l8 4 8-4V7z"/><path d="m4 7 8 4 8-4M12 11v10"/>',
    "repair": '<path d="M14.5 6.5a4 4 0 0 0 5 5L12 19a2.1 2.1 0 0 1-3-3l7.5-7.5"/><path d="M14.5 6.5 17 4l3 3-2.5 2.5"/>',
    "update": '<path d="M20 12a8 8 0 1 1-2.3-5.7"/><path d="M20 4v4.5h-4.5"/>',
    "bottle": '<path d="M10 2.5h4M10.5 2.5v4.2c0 .8-.4 1.4-1 2-1.4 1.2-2 2.6-2 4.3v6.5a2 2 0 0 0 2 2h5a2 2 0 0 0 2-2V13c0-1.7-.6-3.1-2-4.3-.6-.6-1-1.2-1-2V2.5"/><path d="M7.5 14h9"/>',
    "heart": '<path d="M12 20s-7.5-4.4-7.5-10A4.3 4.3 0 0 1 12 7.3 4.3 4.3 0 0 1 19.5 10c0 5.6-7.5 10-7.5 10z"/>',
    "search": '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>',
    "sun": '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
    "moon": '<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>',
    "ok": '<circle cx="12" cy="12" r="9"/><path d="m8 12.5 2.8 2.8L16.5 9.5"/>',
    "warn": '<path d="M12 3.5 2.8 19.5h18.4z"/><path d="M12 10v4.5M12 17.2v.1"/>',
    "muted": '<circle cx="12" cy="12" r="9" stroke-dasharray="3 3"/><path d="M12 8v.1M12 11v5"/>',
    "github": '<path d="M9 19c-4.3 1.4-4.3-2.5-6-3m12 5v-3.5c0-1 .1-1.4-.5-2 2.8-.3 5.5-1.4 5.5-6a4.6 4.6 0 0 0-1.3-3.2 4.2 4.2 0 0 0-.1-3.2s-1.1-.3-3.5 1.3a12.3 12.3 0 0 0-6.2 0C6.5 2.8 5.4 3.1 5.4 3.1a4.2 4.2 0 0 0-.1 3.2A4.6 4.6 0 0 0 4 9.5c0 4.6 2.7 5.7 5.5 6-.6.6-.6 1.2-.5 2V21"/>',
}


def icon(name, cls=""):
    svg = _SVG.format(ICONS[name])
    return svg.replace("<svg ", f'<svg class="{cls}" ', 1) if cls else svg


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


# ---------------------------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------------------------
def fail(path, message):
    sys.exit(f"error: {os.path.relpath(path, ROOT)}: {message}")


def load_games():
    games = []
    for path in sorted(glob.glob(os.path.join(ROOT, "profiles", "*.toml"))):
        d = parse_toml(path)
        g, comp, art = d.get("game", {}), d.get("compatibility", {}), d.get("art", {})
        # Every game comes through a store — Cellar has no store-less or manual-download path —
        # so a profile must name one.
        storekey = g.get("store")
        status = comp.get("status", "untested")
        # A malformed profile fails the build with its filename, rather than shipping a wrong card.
        if not g.get("name") or not g.get("slug"):
            fail(path, "[game] needs both name and slug")
        if storekey not in STORES:
            fail(path, f"store must be one of {', '.join(STORES)} (got {storekey!r}); "
                       "every game comes through a store")
        if status not in STATUS:
            fail(path, f"unknown status {status!r} (expected one of: {', '.join(STATUS)})")
        appid = g.get("steam_appid", "")
        # A profile may bring its own cover; only Steam has one addressable by id.
        portrait = art.get("art_portrait") or (
            f"https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/library_600x900.jpg"
            if appid and storekey == "steam" else "")
        # Every game gets a real cover; the generated placeholder is a fallback for a CDN outage,
        # not a design for a whole store. A Steam game gets one from its AppID; any other store's
        # profile has to bring art_portrait (diablo-4 and witcher-3 show how).
        if not portrait:
            fail(path, "no cover art: add art_portrait under [art] "
                       "(a Steam game gets one from steam_appid)")
        # `needs_live_steam` is the original spelling of `needs_live_session`; both still read.
        needs_client = comp.get("needs_live_session", comp.get("needs_live_steam", True))
        drm = str(comp.get("drm", "")).strip()
        # The Mac it needs and the Mac it is best on (#298, docs/MAC-REQUIREMENTS.md). Every game
        # has both; the app's MacRequirementsTests checks how they were worked out.
        mac = d.get("mac", {})
        mac_min, mac_rec = str(mac.get("mac_minimum", "")).strip(), str(mac.get("mac_recommended", "")).strip()
        if not mac_min or not mac_rec:
            fail(path, "no [mac] section: every game says which Mac it needs and which it is best on "
                       "(mac_minimum, mac_recommended; see docs/MAC-REQUIREMENTS.md)")
        games.append({
            "name": str(g["name"]),
            "slug": str(g["slug"]),
            "api": str(g.get("graphics_api", "")).strip(),
            "drm": DRM_LABELS.get(drm, drm),
            "status": status,
            "mac_min": mac_min,
            "mac_min_memory": mac.get("mac_memory_minimum", ""),
            "mac_rec": mac_rec,
            "mac_rec_memory": mac.get("mac_memory_recommended", ""),
            "store": storekey,
            "client": bool(needs_client),
            "portrait": str(portrait),
            "profile": f"profiles/{os.path.basename(path)}",
        })
    # A store the site doesn't offer yet keeps its profiles valid (checked above) but off the page.
    games = [g for g in games if g["store"] in OFFERED]
    if not games:
        sys.exit("error: no profiles found in profiles/")
    # Playable first, then by name.
    order = list(STATUS)
    return sorted(games, key=lambda x: (order.index(x["status"]), x["name"].lower()))


def latest_release():
    """The newest published release and its installer, or None when it can't be had.

    Resolved at build time because the asset's name has not always been stable — v0.2.0 shipped
    Cellar-0.2.0.dmg, while releases since ship a versionless Cellar.dmg — so a hard-coded
    releases/latest/download/... link can point at nothing. Without an answer the button opens the
    releases page, which is always right, just one click longer.
    """
    if os.environ.get("CELLAR_SITE_OFFLINE") == "1":
        return None
    req = urllib.request.Request(
        f"https://api.github.com/repos/{OWNER_REPO}/releases/latest",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "cellar-gen-site"})
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            rel = json.load(r)
    except (urllib.error.URLError, OSError, ValueError) as e:
        print(f"warning: latest release not resolved ({e}); Download opens the releases page",
              file=sys.stderr)
        return None
    dmgs = [a for a in rel.get("assets", []) if str(a.get("name", "")).endswith(".dmg")]
    if not dmgs:
        print("warning: the latest release has no .dmg; Download opens the releases page",
              file=sys.stderr)
        return None
    # Prefer the versionless name the releases now use.
    dmg = sorted(dmgs, key=lambda a: a["name"] != "Cellar.dmg")[0]
    version = str(rel.get("tag_name", "")).lstrip("v")
    sums = [a for a in rel.get("assets", []) if a.get("name") == "SHA256SUMS.txt"]
    sums_url = str(sums[0]["browser_download_url"]) if sums else None
    return {
        "version": version,
        "url": str(dmg["browser_download_url"]),
        "size": f"{dmg.get('size', 0) / 1_000_000:.1f} MB",
        "notes": str(rel.get("html_url") or f"{RELEASES}/latest"),
        "date": str(rel.get("published_at", ""))[:10],
        "name": str(dmg["name"]),
        "sha256": release_checksum(sums_url, str(dmg["name"])) if sums_url else None,
        "sums_url": sums_url,
    }


def release_checksum(sums_url, name):
    """The SHA-256 the release workflow published for `name`, or None.

    Cellar isn't signed with an Apple Developer ID (docs/SECURITY.md), so macOS can't vouch for the
    download; the published checksum is how a player can. Read from the release's own
    SHA256SUMS.txt, never computed here, so the site shows exactly what the release says.
    """
    req = urllib.request.Request(sums_url, headers={"User-Agent": "cellar-gen-site"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            text = r.read(65536).decode("utf-8", "replace")
    except (urllib.error.URLError, OSError, ValueError) as e:
        print(f"warning: {sums_url} not read ({e}); the page shows no checksum", file=sys.stderr)
        return None
    return parse_checksum(text, name)


def parse_checksum(text, name):
    """The digest for `name` in `shasum -a 256` output (`<hex>  <file>`), or None."""
    for line in text.splitlines():
        parts = line.strip().split()
        if len(parts) == 2 and parts[1].lstrip("*") == name and re.fullmatch(r"[0-9a-f]{64}", parts[0]):
            return parts[0]
    return None


# ---------------------------------------------------------------------------------------------
# Shared chrome
# ---------------------------------------------------------------------------------------------
def head(title, description, path, base=""):
    n = html.escape
    url = SITE_URL + ("" if path == "index.html" else path)
    return f'''<!doctype html>
<html lang="en" class="no-js"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{n(title)}</title>
<meta name="description" content="{n(description)}">
<meta name="theme-color" content="{LIGHT['bg']}" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="{DARK['bg']}" media="(prefers-color-scheme: dark)">
<link rel="canonical" href="{n(url)}">
<meta property="og:type" content="website"><meta property="og:site_name" content="Cellar">
<meta property="og:title" content="{n(title)}"><meta property="og:description" content="{n(description)}">
<meta property="og:url" content="{n(url)}"><meta property="og:image" content="{SITE_URL}icon.png">
<meta name="twitter:card" content="summary">
<link rel="icon" href="{base}icon.png"><link rel="apple-touch-icon" href="{base}icon.png">
{HEAD_JS}
<style>{CSS}</style></head><body>
<a class="skip" href="#main">Skip to content</a>'''


def topbar(current, release, base=""):
    n = html.escape
    pages = [(f"{base}index.html#features", "Features", None),
             (f"{base}index.html#tour", "See It Work", None),
             (f"{base}games.html", "Games", "games"),
             (f"{base}faq.html", "Questions", "faq"),
             (REPO, "GitHub", None)]
    current_mark = ' aria-current="page"'
    links = "".join(
        f'<a href="{n(href)}"{current_mark if key and key == current else ""}>{label}</a>'
        for href, label, key in pages)
    return f'''<header class="top"><div class="wrap">
  <a class="brand" href="{base}index.html"><img src="{base}icon.png" alt="" width="28" height="28">Cellar</a>
  <nav class="nav" aria-label="Main">{links}</nav>
  <button class="icon-btn" id="theme" type="button" aria-pressed="false" aria-label="Switch to dark mode">{icon("sun", "sun")}{icon("moon", "moon")}</button>
  <a class="btn btn-primary btn-small" href="{n(download_href(release))}">Download</a>
</div></header>'''


def checksum_line(release):
    """The download's SHA-256 under the Download button, so it can be checked before opening it."""
    if not release or not release.get("sha256"):
        return ""
    n = html.escape
    sums = f' · <a href="{n(release["sums_url"])}">SHA256SUMS.txt</a>' if release.get("sums_url") else ""
    return (f'\n    <p class="fine sum">SHA-256 of {n(release["name"])}: <code>{n(release["sha256"])}</code>'
            f' · <a href="faq.html#how-do-i-know-the-download-really-is-cellar">how to check it</a>{sums}</p>')


def download_href(release):
    return release["url"] if release else f"{RELEASES}/latest"


def download_detail(release):
    bits = ([f"Version {release['version']}", release["size"]] if release else []) + \
           [f"Apple silicon · macOS {MIN_MACOS} or later"]
    return " · ".join(bits)


def closing_band(release, base=""):
    n = html.escape
    return f'''<section class="band" aria-labelledby="band-h"><div class="wrap">
  <img src="{base}icon.png" alt="" width="88" height="88">
  <h2 id="band-h">Your games are waiting.</h2>
  <p>Download Cellar, sign in to {your_stores("the stores you already use", "the Steam account you already have")}, and play the games you own.</p>
  <a class="btn btn-primary btn-big" href="{n(download_href(release))}">{icon("download")}Download for Mac</a>
  <p class="fine">{n(download_detail(release))} · Free</p>
</div></section>'''


def site_footer(games, base=""):
    playable = sum(1 for g in games if g["status"] == "playable")
    return f'''<footer class="site"><div class="wrap">
  <div class="cols">
    <div><h2>Cellar</h2><ul>
      <li><a href="{RELEASES}/latest">Download</a></li>
      <li><a href="{RELEASES}">All releases</a></li>
      <li><a href="{base}index.html#features">Features</a></li>
      <li><a href="{base}games.html">Supported games</a></li>
    </ul></div>
    <div><h2>Help</h2><ul>
      <li><a href="{base}faq.html">Questions &amp; answers</a></li>
      <li><a href="{base}faq.html#trouble">When something goes wrong</a></li>
      <li><a href="{REPO}/issues">Report a problem</a></li>
    </ul></div>
    <div><h2>Project</h2><ul>
      <li><a href="{REPO}">Source code</a></li>
      <li><a href="{REPO}/blob/main/CONTRIBUTING.md">Add a game</a></li>
      <li><a href="{REPO}/blob/main/LICENSE">Licence (GPL-3.0)</a></li>
      <li><a href="{REPO}/blob/main/docs/LEGAL.md">Legal</a></li>
    </ul></div>
  </div>
  <p class="legal">{len(games)} games set up, {playable} confirmed playable. Cellar is free software
  under GPL-3.0 and is not affiliated with Apple, {", ".join(OWNERS[k] for k in OFFERED)}, CodeWeavers or any game
  publisher; their names appear only to say where a game comes from.</p>
  <p class="legal">Cellar is built on <a href="https://www.winehq.org/">Wine</a>, the open-source
  Windows compatibility layer, and the work of everyone credited in the app&rsquo;s About window.
  The Mac each game needs, and the estimate for untested games, draw on
  <a href="https://www.protondb.com">ProtonDB</a>, Valve&rsquo;s Steam Deck ratings,
  <a href="https://areweanticheatyet.com">AreWeAntiCheatYet</a>,
  <a href="https://www.pcgamingwiki.com">PCGamingWiki</a>,
  <a href="https://www.applegamingwiki.com">AppleGamingWiki</a>, the
  <a href="https://www.codeweavers.com/compatibility">CodeWeavers Compatibility Center</a> and
  <a href="https://steamdb.info">SteamDB</a>, each under its own terms. Cover art belongs to each
  game&rsquo;s publisher.</p>
</div></footer>'''


def scripts(*bodies):
    return "".join(f"<script>{b}</script>" for b in bodies)


# ---------------------------------------------------------------------------------------------
# Landing page
# ---------------------------------------------------------------------------------------------
# Screenshots and video. Real captures of the shipping app only — never a mock-up (docs/SHOWCASE.md
# is the shot list and how to take them). Until a capture is in pages/media/, its slot shows a
# labelled "coming soon" frame carrying the same message, so the page reads complete today and the
# capture drops in without a copy change. An image is <id>.png or <id>.jpg; the video is tour.mp4
# with tour.vtt (captions) and tour-poster.jpg, all three or none.
# ---------------------------------------------------------------------------------------------
MEDIA = os.environ.get("CELLAR_SITE_MEDIA") or os.path.join(ROOT, "pages", "media")
HERO_SHOT = ("hero", "Cellar showing a Steam library on a Mac",
             "Your Steam library in Cellar, with Play one click away.")
# The four feature rows on the home page, each beside its screenshot: (id, title, body, alt).
SHOTS = [
    ("library", "Sign in once. Your whole library is there.",
     "One Steam sign-in covers every game: scan the code with the Steam app on your phone, or use "
     "your password. Cellar then lists <b>exactly the games Steam says you own</b>, and downloads "
     "each one&rsquo;s DLC along with it.",
     "Cellar listing the Windows games in a Steam library"),
    ("game", "Know which Mac a game needs, before you download it.",
     "Every game names the <b>slowest Apple chip it should run on and the one it&rsquo;s best on</b>, "
     "worked out from the publisher&rsquo;s own PC requirements. Nobody tried it on a Mac yet? The "
     "page says so, and gives an estimate of how likely it is to work, and where that came from.",
     "A game's page in Cellar, with the Mac it needs and one button"),
    ("installing", "Press Install, and go do something else.",
     "Cellar downloads the game from your own account and builds its <b>bottle</b>: a sealed space "
     "for that one game, so games never get in each other&rsquo;s way and uninstalling leaves "
     "nothing behind.",
     "Cellar installing a game, with its progress"),
    ("playing", "Then it&rsquo;s just the game.",
     "It opens under <b>its own name and icon in the Dock</b>, full screen or in a window, as you "
     "chose for that game. Switch any time with &#8984;&nbsp;Return.",
     "A Windows game running on a Mac, named in the Dock"),
]
# The launch screen, word for word: LaunchStage.title/detail in
# app/Packages/CellarDomain/Sources/CellarDomain/Launch/LaunchStage.swift, for a Steam game.
LAUNCH_GAME = "Planet Coaster 2"
LAUNCH_STAGES = [
    ("Preparing the bottle", "Checking everything this game needs is in place."),
    ("Opening Steam", "Steam starts in the background, with no window."),
    (f"Starting {LAUNCH_GAME}", "The game itself, under its own name."),
    (f"Waiting for {LAUNCH_GAME} to appear", "Some games take a couple of tries. Cellar handles that."),
    ("Playing", "Quit the game and Cellar closes everything behind it."),
]
TOUR_VIDEO = ("tour", "Pressing Play in Cellar, from the first step to the game.")
IMAGE_EXTS = (".png", ".jpg")


def image_size(path):
    """(width, height) of a PNG or JPEG, from its header, so every <img> reserves its space."""
    with open(path, "rb") as f:
        data = f.read(1 << 16)
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
    i = 2
    while i + 9 < len(data) and data[:2] == b"\xff\xd8":
        if data[i] != 0xFF:
            break
        marker, length = data[i + 1], int.from_bytes(data[i + 2:i + 4], "big")
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            return int.from_bytes(data[i + 7:i + 9], "big"), int.from_bytes(data[i + 5:i + 7], "big")
        i += 2 + length
    raise SystemExit(f"error: {path}: not a PNG or JPEG whose size can be read")


def find_media():
    """The captures present in MEDIA: {id: (filename, (w, h))}, plus the video as {"tour": {...}}."""
    found = {}
    for ident in [HERO_SHOT[0]] + [s[0] for s in SHOTS] + [TOUR_VIDEO[0] + "-poster"]:
        for ext in IMAGE_EXTS:
            path = os.path.join(MEDIA, ident + ext)
            if os.path.exists(path):
                found[ident] = (ident + ext, image_size(path))
                break
    vid = TOUR_VIDEO[0]
    parts = [os.path.exists(os.path.join(MEDIA, f"{vid}.mp4")), os.path.exists(os.path.join(MEDIA, f"{vid}.vtt")),
             f"{vid}-poster" in found]
    if any(parts) and not all(parts):
        sys.exit(f"error: {MEDIA}: the video needs {vid}.mp4, {vid}.vtt (captions) and {vid}-poster.jpg together")
    if all(parts):
        found[vid] = {"src": f"{vid}.mp4", "captions": f"{vid}.vtt", "poster": found.pop(f"{vid}-poster")}
    else:
        found.pop(f"{vid}-poster", None)
    return found


WINDOW_BAR = '<div class="bar" aria-hidden="true"><i></i><i></i><i></i></div>'


def shot_frame(media, ident, alt, soon):
    """A screenshot in a Mac window, or, until it is captured, the same window saying what it will show."""
    n = html.escape
    if ident in media:
        file, (w, h) = media[ident]
        inner = (f'<img loading="lazy" decoding="async" src="media/{n(file)}" width="{w}" height="{h}"'
                 f' alt="{n(alt)}">')
    else:
        inner = (f'<div class="soon" role="img" aria-label="Screenshot coming soon: {n(alt)}">'
                 f'<span class="tag">Screenshot coming soon</span><b>{n(alt)}</b><span>{soon}</span></div>')
    return f'<div class="window">{WINDOW_BAR}{inner}</div>'


def launch_section(media):
    """What pressing Play looks like: the video once captured, the launch steps until then."""
    n = html.escape
    video = media.get(TOUR_VIDEO[0])
    if video:
        (pw, ph) = video["poster"][1]
        visual = (f'<video controls playsinline preload="none" width="{pw}" height="{ph}"'
                  f' poster="media/{n(video["poster"][0])}" aria-describedby="launch-cap">'
                  f'<source src="media/{n(video["src"])}" type="video/mp4">'
                  f'<track kind="captions" src="media/{n(video["captions"])}" srclang="en" label="English" default>'
                  f'</video>')
        cap = TOUR_VIDEO[1]
    else:
        stages = "".join(f'<li><span class="dot" aria-hidden="true"></span><span><b>{n(t)}</b>'
                         f'<small>{n(d)}</small></span></li>' for t, d in LAUNCH_STAGES)
        visual = (f'<ol class="stages" aria-label="The steps Cellar shows while a game starts">{stages}</ol>'
                  f'<span class="tag stages-tag">Video coming soon</span>')
        cap = "The steps are the ones Cellar shows, word for word. A screen recording replaces this soon."
    return f'''
<section class="launch" id="tour" aria-labelledby="launch-h"><div class="wrap launch-grid">
  <div class="section-head">
    <h2 id="launch-h">Press Play. Cellar does the rest.</h2>
    <p>No settings to find and nothing to type. While the game starts, Cellar shows you each step
    in plain words, so a pause never looks like a hang. The first start of a game can take a
    minute or two.</p>
  </div>
  <figure style="margin:0"><div class="window">{WINDOW_BAR}{visual}</div>
    <figcaption id="launch-cap">{cap}</figcaption></figure>
</div></section>'''


# The rest of what Cellar does, as a spec grid under the feature rows: (icon, title, body).
SPECS = [
    ("gauge", "Game Mode",
     "Each game is a proper Mac game to macOS, so Game Mode gives it first call on the CPU and GPU "
     "and lowers Bluetooth latency for controllers and AirPods."),
    ("chip", "Drawn by Metal",
     "Graphics run on your Mac&rsquo;s own GPU, the way Mac games draw. If a game looks wrong one "
     "way, Cellar knows a second way to try."),
    ("window", "Full screen or a window",
     "Choose per game, and switch while playing with &#8984;&nbsp;Return."),
    ("controller", "Controllers",
     "Cellar shows which controllers are connected, and what each game is known to do with one."),
    ("dock", "Its own name in the Dock",
     "The game shows as itself in the Dock, in &#8984;&nbsp;Tab and in Force Quit. Steam stays out of "
     "sight."),
    ("dlc", "DLC included",
     "The expansions you own download with the game and are there when it starts."),
    ("repair", "Repairs itself",
     "Before a game starts, Cellar checks what it needs and puts back anything damaged or missing. "
     "You never open Terminal."),
    ("update", "Keeps itself current",
     "Cellar tells you when there&rsquo;s a new version and installs it in one click. What it knows "
     "about games updates too."),
    ("bottle", "A bottle per game",
     "Games never share settings or files, so fixing one can&rsquo;t break another, and removing "
     "one removes all of it."),
]

STEPS = [
    ("Download and open Cellar",
     "Drag it to Applications. macOS asks once before it opens an app from the web: "
     "<a href=\"faq.html#macos-says-cellar-can-t-be-opened\">here&rsquo;s the one extra click</a>."),
    ("Sign in to Steam",
     "With the QR code and the Steam app on your phone, or your password. Meanwhile Cellar gets "
     "ready in the background: a few gigabytes, once."),
    ("Pick a game and press Play",
     "Install it, then Play. The first time takes a few minutes longer; after that it&rsquo;s one "
     "click."),
]

# Sponsoring (the sponsor page and its link land with #299). While this is empty the page says
# sponsoring opens soon instead of showing a button that leads nowhere. Nothing is ever paywalled.
SPONSOR_URL = ""


def card(g):
    n = html.escape
    label, cls, _meaning = STATUS[g["status"]]
    store = STORES[g["store"]]
    art = (f'<img loading="lazy" decoding="async" src="{n(g["portrait"])}" alt="" width="600" height="900"'
           f' onerror="this.classList.add(\'broken\')">') if g["portrait"] else ""
    # Every game comes through its store; this only says whether the store's app also has to be
    # running while you play. Worded so it never reads as "no store".
    client = (f"{n(store)} app runs alongside" if g["client"] else "Just the game")
    facts = []
    if g["api"]:
        facts.append(("Graphics", n(g["api"])))
    facts.append(("DRM", n(g["drm"]) or "Not stated"))
    facts.append(("While playing", client))
    # Estimated from the publisher's PC requirements, not tested; the title says so on hover.
    facts.append(("Needs", f'<span title="Estimated from the publisher&rsquo;s PC requirements">'
                           f'{n(g["mac_min"])}, {n(str(g["mac_min_memory"]))} GB</span>'))
    facts.append(("Best on", f'{n(g["mac_rec"])}, {n(str(g["mac_rec_memory"]))} GB'))
    dl = "".join(f"<dt>{k}</dt><dd>{v}</dd>" for k, v in facts)
    # Which store a game is from only tells games apart once the site offers more than one.
    chip = f'<div><span class="chip {n(g["store"])}">{n(store)}</span></div>' if len(OFFERED) > 1 else ""
    return f'''
    <li class="card" data-name="{n(g['name'].lower())}" data-status="{n(g['status'])}" data-store="{n(g['store'])}">
      <div class="art"><span class="ph" aria-hidden="true">{n(g['name'])}</span>{art}<span class="badge {cls}">{icon(cls)}{n(label)}</span></div>
      <div class="meta">
        <h3>{n(g['name'])}</h3>
        {chip}
        <dl class="facts">{dl}</dl>
        <a class="more" href="{REPO}/blob/main/{n(g['profile'])}">Technical details<span class="sr-only"> for {n(g['name'])}</span></a>
      </div>
    </li>'''


GAMES_CAP = 10  # cards the home page shows before "Show all games" (Kenneth, 2026-11-03)


def games_block(games, cap=None):
    """The searchable games list: the whole of games.html, and the short version on the home page.

    One component in both places. With `cap`, at most that many matching cards show, and a link
    under them opens games.html with the same search and filters; without JavaScript the first
    `cap` cards show and the link opens the full list."""
    total = len(games)
    stores_present = [k for k in STORES if any(g["store"] == k for g in games)]
    statuses_present = [k for k in STATUS if any(g["status"] == k for g in games)]
    store_opts = [] if len(stores_present) < 2 else [("all", "All stores", total)] + [
        (k, STORES[k], sum(1 for g in games if g["store"] == k)) for k in stores_present]
    status_opts = [("all", "Any status", total)] + [
        (k, STATUS[k][0], sum(1 for g in games if g["status"] == k)) for k in statuses_present]
    cards = "".join(card(g) for g in games)
    legend = "".join(
        f'<li>{icon(cls, cls)}<span><b>{label}</b> — {meaning}</span></li>'
        for _k, (label, cls, meaning) in STATUS.items())
    capped = cap is not None and total > cap
    shown = min(total, cap) if capped else total
    count = f"Showing {shown} of {total} games" if capped else f"Showing all {total} games"
    cap_attr = f' data-cap="{cap}"' if capped else ""
    more = (f'\n    <p class="more-games"><a class="btn btn-ghost-dark" id="more" href="games.html">'
            f'Show all {total} games</a></p>') if capped else ""
    return f'''<div class="toolbar" role="search" aria-label="Filter games">
      <div class="search">{icon("search")}<label class="sr-only" for="q">Search games</label>
        <input id="q" type="search" placeholder="Search {total} games" autocomplete="off"></div>
      {seg("store", "Store", store_opts) if store_opts else ""}
      {seg("status", "Status", status_opts)}
    </div>
    <p class="count" id="count" role="status" aria-live="polite">{count}</p>
    <ul class="grid" id="grid"{cap_attr}>{cards}
    </ul>
    <div class="empty" id="empty" hidden><p>No games match those filters.</p>
      <button class="btn btn-primary btn-small" id="reset" type="button">Show all games</button></div>{more}
    <ul class="legend">{legend}</ul>'''


DONT_SEE = f'''<div class="callout"><h3>Don&rsquo;t see your game?</h3>
      <p>Each game is one small text file saying where it comes from, how it starts and what you saw
      when you played it. <a href="{REPO}/blob/main/CONTRIBUTING.md">Add one</a>, or read
      <a href="faq.html#games">how this list works</a>.</p></div>'''


def seg(key, label, options):
    """A row of toggle buttons: one pressed at a time, each saying how many games it would show."""
    buttons = "".join(
        f'<button type="button" data-value="{html.escape(value)}" aria-pressed="{"true" if i == 0 else "false"}">'
        f'{html.escape(text)}<span class="n" aria-hidden="true">{count}</span>'
        f'<span class="sr-only">, {count} games</span></button>'
        for i, (value, text, count) in enumerate(options))
    return f'<div class="seg" role="group" aria-label="{html.escape(label)}" data-key="{key}">{buttons}</div>'


def render_index(games, release):
    n = html.escape
    total = len(games)
    media = find_media()

    if HERO_SHOT[0] in media:
        file, (w, h) = media[HERO_SHOT[0]]
        hero_visual = (f'<div class="window">{WINDOW_BAR}<img src="media/{n(file)}" width="{w}" height="{h}"'
                       f' alt="{n(HERO_SHOT[1])}"></div>')
    else:
        hero_visual = shot_frame(media, HERO_SHOT[0], HERO_SHOT[1], HERO_SHOT[2])

    rows = "".join(
        f'<li class="row"><div class="copy"><h3>{title}</h3><p>{body}</p></div>'
        f'<figure>{shot_frame(media, sid, alt, "")}</figure></li>'
        for sid, title, body, alt in SHOTS)
    specs = "".join(f'<li>{icon(ic)}<h3>{title}</h3><p>{body}</p></li>' for ic, title, body in SPECS)
    steps = "".join(f"<li><h3>{title}</h3><p>{body}</p></li>" for title, body in STEPS)
    teaser_ids = ["what-is-cellar", "which-macs-does-it-work-on",
                  "macos-says-cellar-can-t-be-opened", "what-about-games-with-anti-cheat"]
    teaser = "".join(qa_html(q, a) for _t, _anchor, _l, qs in FAQ_SECTIONS for q, a in qs
                     if slugify(q) in teaser_ids)
    sponsor = (f'<a class="btn btn-ghost" href="{n(SPONSOR_URL)}">{icon("heart")}Sponsor Cellar</a>'
               if SPONSOR_URL else
               f'<span class="pending">{icon("heart")}Sponsoring opens soon</span>')

    release_line = (f'Version {n(release["version"])} · <a href="{n(release["notes"])}">what&rsquo;s new</a> · '
                    if release else "")
    ld = json.dumps({
        "@context": "https://schema.org", "@type": "SoftwareApplication", "name": "Cellar",
        "operatingSystem": f"macOS {MIN_MACOS} or later (Apple Silicon)",
        "applicationCategory": "GameApplication", "url": SITE_URL,
        "downloadUrl": download_href(release), "license": "https://www.gnu.org/licenses/gpl-3.0.html",
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        **({"softwareVersion": release["version"]} if release else {}),
    }).replace("<", "\\u003c")

    return f'''{head("Cellar — Play your Windows games on your Mac",
                 f"Cellar plays the Windows games you own on {stores_phrase()} on an Apple silicon "
                 "Mac. Sign in once, pick a game, press Play. Free and open source.", "index.html")}
{topbar("home", release)}
<main id="main">
<section class="hero" aria-labelledby="hero-h"><div class="wrap">
  <img class="appicon" src="icon.png" alt="" width="96" height="96">
  <h1 id="hero-h">Play your Windows {stores_phrase()} games on your Mac.</h1>
  <p class="lede">Sign in once, pick a game you own and press Play. Cellar sets up the rest.
  Free, and made for Apple silicon.</p>
  <div class="ctas">
    <a class="btn btn-primary btn-big" href="{n(download_href(release))}">{icon("download")}Download for Mac</a>
    <a class="chev" href="#games">See the {total} games</a>
  </div>
  <p class="fine">{release_line}{n(download_detail(release))} · Free and open source<br>
  First time opening it? macOS asks once: <a href="faq.html#macos-says-cellar-can-t-be-opened">here&rsquo;s the one extra click</a>.</p>{checksum_line(release)}
  <div class="stage">{hero_visual}</div>
</div></section>

<div class="wrap">
  <section class="block" id="features" aria-labelledby="features-h">
    <div class="section-head">
      <h2 id="features-h">Your games, on your Mac, the Mac way.</h2>
      <p>Cellar knows how each game likes to be set up, so you never see a setting you
      don&rsquo;t understand.</p></div>
    <ol class="rows">{rows}</ol>
  </section>
</div>
{launch_section(media)}
<div class="wrap">
  <section class="block" id="details" aria-labelledby="details-h">
    <div class="section-head"><h2 id="details-h">The details, already handled.</h2>
      <p>The things you&rsquo;d otherwise go looking for in a forum.</p></div>
    <ul class="specs">{specs}</ul>
  </section>
</div>

<section class="free" id="free" aria-labelledby="free-h"><div class="wrap">
  <div class="section-head center"><h2 id="free-h">Free. Not free for now. Free.</h2>
    <p>Cellar will never be sold, and nothing in it is locked behind a payment.</p></div>
  <ul class="three">
    <li><h3>Open source</h3><p>Every line is public under GPL-3.0. Anyone can read it, fix it, or
      add a game.</p></li>
    <li><h3>No account, no tracking</h3><p>There is no Cellar account. Cellar sends nothing about
      you or your games anywhere.</p></li>
    <li><h3>Your games, untouched</h3><p>Games come from your own Steam account, and their copy
      protection runs as the publisher built it.</p></li>
  </ul>
  <div class="sponsor">
    <p>Want to help? Sponsoring buys Macs of every chip to test games on, so more of them can be
    called playable. Entirely optional; it unlocks nothing.</p>
    {sponsor}
  </div>
</div></section>

<div class="wrap">
  <section class="block" id="how" aria-labelledby="how-h">
    <div class="section-head"><h2 id="how-h">Up and running in three steps.</h2></div>
    <ol class="steps">{steps}</ol>
  </section>

  <section class="block" id="games" aria-labelledby="games-h">
    <div class="section-head">
      <h2 id="games-h">The games, and what&rsquo;s known about each.</h2>
      <p><b>Playable</b> means someone played it on the Mac named on its card. <b>Untested</b> means
      Cellar knows how to set it up and nobody has confirmed it yet. Search all {total}, or
      <a href="games.html">see the full list</a>.</p></div>
    {games_block(games, GAMES_CAP)}
  </section>

  <section class="block" id="requirements" aria-labelledby="req-h">
    <div class="section-head"><h2 id="req-h">What you need.</h2>
      <p>Cellar checks your Mac when it opens, and says what is missing before anything fails.</p></div>
    <dl class="reqs">
      <div><dt>Mac</dt><dd>Any Mac with Apple silicon: M1 or later. Each game says which chip it needs.</dd></div>
      <div><dt>macOS</dt><dd>macOS {MIN_MACOS} or later. Every Apple silicon Mac can run it.</dd></div>
      <div><dt>Account</dt><dd>A {stores_phrase("or")} account with the games you want to play.</dd></div>
      <div><dt>Space</dt><dd>Room for your games, plus a few gigabytes Cellar downloads once.</dd></div>
    </dl>
  </section>

  <section class="block" id="faq" aria-labelledby="faq-h">
    <div class="section-head"><h2 id="faq-h">Questions people ask first.</h2></div>
    <div class="qa-list">{teaser}</div>
    <a class="chev more-link" href="faq.html">All questions and answers</a>
  </section>
</div>

{closing_band(release)}
</main>
{site_footer(games)}
<script type="application/ld+json">{ld}</script>
{scripts(THEME_JS, GAMES_JS)}
</body></html>
'''


# ---------------------------------------------------------------------------------------------
# FAQ
# ---------------------------------------------------------------------------------------------
# The FAQ, as data: (section title, anchor, one-line lede, [(question, answer HTML)]). Each
# question's anchor is its slug, so any answer can be linked to directly.
#
# Prose rather than generated, because these answer *how Cellar behaves* — but every claim here is
# one the app or the docs already make. Nothing promises a state Cellar cannot check, and nothing
# is softened to sound better than it is (skills/ux.md). When behaviour changes, this changes.
FAQ_SECTIONS = [
    ("Getting started", "start", "What Cellar is, and what it needs from your Mac.", [
        ("What is Cellar?",
         "<p>Cellar plays <b>Windows games on Apple Silicon Macs</b>. You sign in to "
         f"{stores_phrase('or')}, pick a game you own and press Play. Cellar installs it, gives it "
         "its own space on your Mac and sets up what it needs, and the game runs much as it does on "
         "a PC. Your Mac does not become one.</p>"
         "<p>It is the same idea as Valve's Proton on Linux, aimed at macOS, and it is free and "
         "open source under GPL-3.0.</p>"),
        ("What's under the hood?",
         "<p>For the curious: each game gets a <i>bottle</i>, a small self-contained Windows "
         "environment built on <a href=\"https://www.winehq.org/\">Wine</a>. Wine answers the "
         "Windows calls a game makes, as it makes them. A graphics layer — Apple's D3DMetal, or "
         "DXVK on MoltenVK — turns the game's Direct3D into Metal on the Apple GPU. Wine itself "
         "runs as an Intel app under Rosetta 2.</p>"
         "<p>What each game needs is written down in a <i>profile</i>, one small file per game in "
         f"the <a href=\"{REPO}/tree/main/profiles\">open profile database</a>: which graphics "
         "layer to use and which to fall back to, and the fixes it is known to need. If you prefer "
         "a terminal, the <code>cellar</code> command-line tool does everything the app does.</p>"),
        ("Do I need a Windows licence, Boot Camp, or a virtual machine?",
         "<p>None of the three. Wine is not an emulator and not a virtual machine — it answers the "
         "Windows API calls a game makes, as it makes them. There is no Windows install to "
         "maintain and no licence to buy.</p>"),
        ("Which Macs does it work on?",
         f"<p><b>Apple Silicon only</b> (M1 and later), on macOS {MIN_MACOS} or newer — the newest "
         "macOS every M1 Mac can run, so no Apple Silicon Mac is left out. The graphics work runs "
         "on the Apple GPU, so an Intel Mac is out of scope.</p>"
         "<p>Open the app and it tells you what your Mac is missing, rather than failing later "
         "for an unclear reason.</p>"),
        ("How do I install it?",
         "<p>Download the DMG, drag Cellar to Applications, and open it. On first launch it "
         "introduces itself, asks once for the folders where Windows games keep their saves, and "
         f"offers to sign you in to {your_stores('your stores', 'Steam')}. You can skip signing in — Cellar still opens, and "
         "signing in later works identically from <b>Accounts</b> (⌘⇧A) or <b>Settings → Manage "
         "accounts</b>.</p>"
         "<p>Cellar downloads the Wine runner itself the first time a game needs one. No Terminal "
         "required, though there is a full <code>cellar</code> command-line tool if you prefer "
         "one.</p>"),
        ("macOS says Cellar can't be opened.",
         "<p>Cellar is free software and isn't signed with a paid Apple Developer ID, so Apple "
         "hasn't notarised it and macOS can't vouch for who made it. The first time you open it, "
         "macOS stops it once. On macOS 27 there is no Open button in that first message — "
         "right-clicking and choosing Open no longer skips it — so allow it from Settings:</p>"
         "<ol><li>Drag Cellar to <b>Applications</b> and double-click it. macOS says "
         "<b>“Cellar” Not Opened</b>. Click <b>Done</b> — not <b>Move to Trash</b>.</li>"
         "<li>Open <b>System Settings → Privacy &amp; Security</b> and scroll down to "
         "<b>Security</b>. You'll see <b>“Cellar” was blocked to protect your Mac</b>. Click "
         "<b>Open Anyway</b>. The button only shows for about an hour after step 1; if it's gone, "
         "do step 1 again.</li>"
         "<li>macOS asks once more. Click <b>Open Anyway</b> and confirm with your password or "
         "Touch ID.</li></ol>"
         "<p>You only do this once; after that Cellar opens normally, and its updates are checked "
         "against Cellar's own signing key. Before you do it, you can "
         "<a href=\"faq.html#how-do-i-know-the-download-really-is-cellar\">check the download</a> is the "
         "one we published.</p>"
         "<p>Don't use a Terminal command that removes the quarantine flag: it skips the same "
         "check for everything else it touches.</p>"),
        ("How do I know the download really is Cellar?",
         "<p>Every release publishes the SHA-256 checksum of each download, in "
         "<code>SHA256SUMS.txt</code> on the release page and under the Download button on this "
         "site. Open <b>Terminal</b> and run:</p>"
         "<pre><code>shasum -a 256 ~/Downloads/Cellar.dmg</code></pre>"
         "<p>The long line of letters and digits it prints must match the published one exactly. "
         "If it doesn't, don't open the file: delete it, download it again from this site or "
         f"<a href=\"{RELEASES}\">GitHub Releases</a>, and "
         f"<a href=\"{REPO}/issues/new\">tell us</a> if it still doesn't match.</p>"
         "<p>Get Cellar only from this site or the GitHub releases page. Any other copy is not "
         "ours.</p>"),
        ("Is it free? Do I need an account with you?",
         "<p>Free, GPL-3.0, and there is no Cellar account, no sign-up and no telemetry. The only "
         f"{your_stores('accounts involved are the game stores you already have', 'account involved is the Steam account you already have')}.</p>"),
    ]),

    ("Accounts and signing in", "accounts",
     "Why Cellar asks, what it can see, and what it deliberately won't claim.", [
        ("Why do I have to sign in at all?",
         "<p>Because the games are <b>yours</b>. Cellar does not host or distribute game files — it "
         f"installs from your own {stores_phrase('or')} account, the way those clients would on a "
         "PC. No sign-in, no library.</p>"),
        (your_stores("Once per store, or once per game?", "Once, or once per game?"),
         f"<p><b>Once{your_stores(' per store', '')}.</b> One Steam sign-in covers your whole Steam library — both what "
         "you own and downloading it. "
         + only("gog", "GOG is one token Cellar holds for the account. ") + "That is why "
         "signing in lives on the <b>Accounts</b> screen — your account at the bottom of the sidebar, ⌘⇧A, or "
         "Settings → Manage accounts — and not on each game's page.</p>"),
        ("Does Cellar see my password?",
         "<p>Cellar never keeps it. The quickest way in is Steam's own QR code: you approve it in the "
         "Steam mobile app and type no password at all. Without the app, you can use your account "
         "name and password, with a Steam Guard code if Steam asks for one; Cellar hands them straight "
         "to Steam and keeps only the sign-in Steam gives back, in your macOS Keychain. "
         + only("gog", "GOG uses its normal login page and hands back an OAuth token, which Cellar "
                "keeps in your macOS Keychain. ")
         + only("battlenet", "Battle.net's sign-in happens entirely inside Blizzard's client.")
         + "</p>"),
    ] + ([] if "battlenet" not in OFFERED else [
        ("Why does Battle.net say “Add” instead of “Sign in”?",
         "<p>Because Blizzard writes nothing readable that says who is signed in, or which games "
         "that account owns. Steam and GOG both answer those questions; Battle.net does not.</p>"
         "<p>So Accounts asks you once whether Battle.net is yours — <b>Add</b> — and Cellar then "
         "shows its games, saying plainly that it cannot check you own them. You sign in inside "
         "Blizzard's own window when you open it. Where Cellar looks oddly modest about what it "
         "knows, this is usually why.</p>"),
    ]) + [
        ("Why does a Windows Steam run inside the bottle?",
         "<p>Cellar downloads Steam games with your one sign-in, without starting a Steam window. "
         "But many Steamworks games check for a <i>running</i> Steam while they play, so for those "
         "Cellar installs the Windows Steam client in the bottle and starts it beside the game. "
         "It is a dependency of the game, not a second account. Cards that say <b>Just the game</b> "
         "under While playing skip it: the game still comes from your Steam account, it just "
         "doesn't need Steam running to play.</p>"),
        ("Can I sign out?",
         "<p>Yes. Accounts offers Sign out for each session Cellar itself holds. "
         + ("The Steam client and Battle.net are signed out from inside their own windows, because "
            "that is where those sessions actually live.</p>" if "battlenet" in OFFERED else
            "The Steam client inside a bottle is signed out from its own window, because that is "
            "where that session actually lives.</p>")),
    ]),

    ("Games and compatibility", "games", "What the ratings mean, and why a game might be missing.", [
        ("What do Playable, Experimental and Untested mean?",
         "<ul>"
         "<li><b>Playable</b> — someone ran it on named hardware and the profile says which Mac.</li>"
         "<li><b>Experimental</b> — it runs, with caveats worth reading before you count on it.</li>"
         "<li><b>Untested</b> — the profile exists; nobody has confirmed it. Cellar says so rather "
         "than guessing.</li>"
         "</ul>"
         "<p>Every card on the games list is generated from a profile in the repository, so this "
         "site cannot claim more than the profile does.</p>"),
        ("Which Mac do I need for a game?",
         "<p>Every card says two Macs. <b>Needs</b> is the Mac the game starts and plays on at low "
         "settings; <b>Best on</b> is the Mac for a smooth game at good settings. Both come from the "
         "publisher&rsquo;s own PC requirements: Cellar matches the graphics card they name to the "
         "Apple chip that draws as well, with room for what running a Windows game on a Mac costs, "
         "and adds the PC&rsquo;s memory to the card&rsquo;s, because a Mac shares one pool between "
         "the two.</p>"
         "<p>It is an estimate, not a test. Chips are compared by their graphics, so an M2 Pro or "
         "an M1 Max covers a game that is best on an M5; the game&rsquo;s page in the app says how "
         "your own Mac compares. "
         f"How the matching works: <a href=\"{REPO}/blob/main/docs/MAC-REQUIREMENTS.md\">MAC-REQUIREMENTS.md</a>.</p>"),
        ("My game isn't listed. Can I still play it?",
         "<p>Often, yes — the list is what has been <i>profiled</i>, not the limit of what works. A "
         "profile is a small text file naming the game's store, its AppID or install folder, its "
         "executable and graphics API, and which backend to use. Copy the closest existing one and "
         f"adjust it; see <a href=\"{REPO}/blob/main/CONTRIBUTING.md\">CONTRIBUTING.md</a>.</p>"
         "<p>Adding a profile is also how a game reaches this site: it is rebuilt from the profiles "
         "every time one changes.</p>"),
        ("What about games with anti-cheat?",
         "<p>Competitive games with kernel-level anti-cheat generally do not run, and Cellar will "
         "not make them. It <b>never circumvents DRM or anti-cheat</b> — protection runs "
         "untouched, exactly as the publisher shipped it. Where Cellar "
         "knows of an anti-cheat problem it says so plainly, rather than letting you discover it "
         "after a 60&nbsp;GB download.</p>"),
        ("Does the store's client have to be running while I play?",
         "<p>It depends on the game, and its card says which. Steamworks titles usually want a live "
         "Steam session. " + only("gog", "GOG's games are DRM-free, so nothing needs to run beside them. ") + "Either "
         "way the game is installed from your own store account; cards that say <b>Just the "
         "game</b> under While playing simply don't need the store's app running beside it.</p>"),
    ]),

    ("Performance", "performance", "What to expect, and the levers that exist.", [
        ("How fast is it, really?",
         "<p>Expect a cost against the same hardware running a native game: you are paying for API "
         "translation, and for x86 code under Rosetta 2. How much depends far more on the game than "
         "on Cellar — CPU-bound simulation games feel it most, GPU-bound ones least.</p>"
         "<p>Each profile's notes name the Mac the numbers came from, because “it runs well” means "
         "nothing without that.</p>"),
        ("What are D3DMetal and DXVK?",
         "<p>Two routes from Direct3D to Metal. <b>D3DMetal</b> is Apple's own translation layer "
         "(from the Game Porting Toolkit) and is usually the faster one. <b>DXVK</b> translates "
         "Direct3D to Vulkan, which MoltenVK then puts onto Metal — slower in most cases, but it "
         "works in places D3DMetal does not. Each profile names a backend, and a fallback wherever "
         "the other one can run the game, so a game that misbehaves on one can be run on the other. "
         "DXVK stops at DirectX 11, so a game made only for DirectX 12 has D3DMetal alone.</p>"),
        ("Can I see an FPS counter?",
         "<p>Yes — <b>Settings → Show Metal performance overlay (FPS)</b> adds an FPS and frametime "
         "HUD to games launched from Cellar. To measure a whole session and see what limits it, run "
         "<code>cellar perf measure &lt;game&gt;</code>.</p>"),
    ]),

    ("Controllers and racing wheels", "controllers",
     "What reaches the game today, and the set-up that happens outside Cellar.", [
        ("Can I play with a controller?",
         "<p>Usually, yes. Xbox, PlayStation (DualSense, DualShock&nbsp;4) and Switch Pro "
         "controllers connect to your Mac the normal way — pair them in <b>System Settings → "
         "Bluetooth</b>, or plug them in over USB. There is nothing to install.</p>"
         "<p>Wine then hands the pad to the game, as an Xbox controller where it can. Whether a "
         "given game plays well with one is up to the game: its page shows what the pad is called "
         "and what its profile records about controllers, and says so when nobody has recorded it "
         "yet. <code>cellar controllers</code> lists what your Mac can see right now.</p>"),
        ("macOS asks whether Cellar may “receive keystrokes from any application”.",
         "<p>Allow it. That is how macOS names <b>Input Monitoring</b>, and Wine needs it to read "
         "a controller or wheel at all: without it a pad your Mac sees never reaches the game.</p>"
         "<p>If you said no, open <b>System Settings → Privacy &amp; Security → Input "
         "Monitoring</b>, turn Cellar on (or your terminal, if you start games with the "
         "<code>cellar</code> command), then quit and reopen the game. <code>cellar doctor</code> "
         "shows where the setting stands.</p>"),
        ("My controller's buttons are wrong, or the game doesn't see it.",
         "<ul>"
         "<li><b>A Steam game started through Steam</b> gets the pad through <i>Steam Input</i>, "
         "which can remap it. Change that in Steam's controller settings for the game: on, to make "
         "a PlayStation or Switch pad act as an Xbox one; off, to give the game the pad as it is.</li>"
         "<li><b>Check Input Monitoring</b>, as above.</li>"
         "<li><b>Run <code>cellar doctor</code></b>. Its <i>Controller layer</i> line says whether "
         "the Wine runner can present PlayStation and Switch pads as Xbox ones; without that, an "
         "Xbox pad is the safest choice.</li>"
         "</ul>"),
        ("Can I use a racing wheel, like a Fanatec, Logitech or Thrustmaster?",
         "<p>Cellar recognises wheel bases, pedals and shifters from Fanatec, Logitech, Thrustmaster "
         "and MOZA, lists them on the game's page and in <code>cellar controllers</code>, and Wine "
         "passes them to the game as a Windows game controller. Steering, pedals and buttons can "
         "reach a racing game that way.</p>"
         "<p><b>Force feedback depends on the wheel.</b> macOS only drives a wheel's motor through "
         "a driver from the wheel's maker, and none of them ships one for Apple Silicon Macs. So "
         "Cellar brings its own: a build of SDL that talks to the wheel over USB, which Wine uses "
         "in place of the runner's.</p>"
         "<ul>"
         "<li><b>"
         "Fanatec CSL DD, GT DD Pro, ClubSport DD, Podium DD1 and DD2, CSL Elite, ClubSport V2 and V2.5, CSR Elite and Porsche 911"
         "</b> — force feedback is driven by Cellar's own Fanatec driver. The base must be in PC "
         "mode.</li>"
         "<li><b>Logitech G29, G27, G25, Driving Force GT and Driving Force Pro</b> — force "
         "feedback is driven by Cellar.</li>"
         "<li><b>"
         "Thrustmaster T300 RS, T300 Ferrari Edition, TX, T248, TS-XW and TS-PC"
         "</b> — force feedback is driven by Cellar's own Thrustmaster driver. A T300 starts in a "
         "generic mode; Cellar switches it into its own mode when a game starts, the way "
         "Thrustmaster's Windows driver does, so it briefly disconnects and comes back.</li>"
         "<li><b>MOZA, Thrustmaster's T150, T500 and TMX, and Logitech's G920 and G923</b> — "
         "steering, pedals and buttons, but no force feedback yet.</li>"
         "</ul>"
         "<p>Cellar's drivers are new. If force feedback feels wrong, report it with the wheel and "
         "the game.</p>"
         "<p><b>Fanatec bases start at half strength.</b> A direct-drive base at full torque can "
         "hurt a hand, so Cellar caps it until you choose otherwise. The base's own force-feedback "
         "setting (FF in its tuning menu) still applies on top. To change it, open Cellar's "
         "<b>Settings › General › Racing wheels</b> and pick a strength; it applies to every wheel "
         "Cellar drives from a game's next launch (or <code>cellar controllers strength 75</code>). "
         "Logitech and Thrustmaster wheels start at the game's own strength. To turn Cellar's "
         "Fanatec and Thrustmaster drivers off, start the game with "
         "<code>CELLAR_FFB_DISABLE=1</code>.</p>"
         "<p>The game's page and <code>cellar controllers</code> say which of these your wheel "
         "is. Results per wheel and per game are still being collected, and what has been tested is "
         "recorded in the game's profile.</p>"),
        ("What do I have to set up on the wheel itself?",
         "<p>Most of it happens outside Cellar, once, and some of it needs a Windows PC because the "
         "makers only publish their tools for Windows:</p>"
         "<ul>"
         "<li><b>Fanatec</b> — put the base in <b>PC mode</b>, not Compatibility (PlayStation/Xbox) "
         "mode; its manual shows how. Update the firmware first on a Windows PC with Fanatec's own "
         "software: Fanatec offers no Mac app, and a base on old firmware may not show up.</li>"
         "<li><b>Logitech</b> — macOS recognises the G29 and G920 by itself, with nothing to "
         "install. Firmware updates go through Logitech G&nbsp;HUB; if it doesn't list your wheel "
         "on the Mac, update it once on a Windows PC.</li>"
         "<li><b>Thrustmaster</b> — set the base to its PC mode and connect it over USB. "
         "Thrustmaster's drivers and firmware are Windows-only, and without the driver some bases "
         "report the pedals as buttons, which most racing games cannot use. There is nothing to "
         "install for force feedback: Cellar switches a T300 into the right mode itself.</li>"
         "<li><b>MOZA</b> — update the firmware and set the steering angle in MOZA Pit House on a "
         "Windows PC first; the base keeps those settings.</li>"
         "</ul>"
         "<p>Then plug the wheel into the Mac, allow Input Monitoring when macOS asks, and pick "
         "the wheel in the game's own controls menu.</p>"),
    ]),

    ("When something goes wrong", "trouble", "The usual causes, in the order worth checking.", [
        ("The first set-up is taking ages. Is it stuck?",
         "<p>Probably not. The first game downloads a Wine runner and builds a fresh bottle, which "
         "takes a few minutes on a good connection; later games reuse the runner and are much "
         "quicker. Cellar shows what it is running while it works — if the activity log is still "
         "moving, let it finish.</p>"),
    ] + ([] if "battlenet" not in OFFERED else [
        ("A store window opened and is waiting for me.",
         "<p>Expected, for Battle.net: Blizzard's installer has no silent mode, so its window "
         "genuinely needs a few clicks. Cellar warns you before opening one rather than appearing "
         "to hang and being force-quit. Steam's installer does run silently.</p>"),
    ]) + [
        ("The game won't start.",
         "<ul>"
         "<li>Read the game's page — it names the step it is actually waiting on.</li>"
         "<li>Check you are signed in to that game's store (Accounts, ⌘⇧A).</li>"
         "<li>Try the profile's fallback backend if the failure looks graphical.</li>"
         "<li>Run <code>cellar doctor</code> for a machine-level check.</li>"
         "</ul>"),
        ("Where are the logs?",
         "<p><b>Settings → Open logs folder</b>, or on disk at "
         "<code>~/Library/Application&nbsp;Support/Cellar/logs</code>. Everything Cellar keeps — "
         "runners, bottles, caches and logs — lives under that one folder, which Settings can also "
         "open for you.</p>"),
        ("How do I report a problem?",
         f"<p>Open an issue on <a href=\"{REPO}/issues\">GitHub</a>. The details that help: your "
         "Mac and macOS version, the game and its profile, which backend you used, and the log from "
         "the run that failed.</p>"),
        ("How do I remove a game, or Cellar itself?",
         "<p><code>cellar uninstall &lt;game&gt;</code>, or the <b>•••</b> menu on the game's page "
         "in the app. Cellar shows the plan first — every path it will delete, with its size, and "
         "what it will keep — and asks before anything goes. Add <code>--dry-run</code> to see that "
         "plan without deleting anything.</p>"
         "<p>What it keeps: your store sign-in, the Wine runner, and the shared Steam install with "
         "every other game in it, so re-installing is just the download. Add <code>--bottle</code> "
         "to take the bottle too — its Wine prefix, registry and the store client inside it.</p>"
         "<p>To remove Cellar entirely, <code>cellar reset --everything</code>. Cellar does not "
         "live in one folder — besides <code>~/Library/Application&nbsp;Support/Cellar</code> it "
         "writes launcher apps into <code>~/Applications</code>, adds entries to your Steam "
         "library" + only("gog", ", and keeps a GOG sign-in in your login keychain") + ". That command takes all of it, "
         "plus the app and the <code>cellar</code> command themselves, and shows you the list "
         "first. Without <code>--everything</code> it stops short of the app and the command, so "
         "you can carry on using Cellar.</p>"),
    ]),

    ("Legal and licensing", "legal", "What Cellar ships, and what it deliberately does not.", [
        ("Is this legal?",
         "<p>Cellar is a compatibility layer. It runs software <i>you own</i>, from accounts you "
         "already have, and it does not modify, crack or bypass any protection. Wine has been doing "
         "exactly this, lawfully, for decades.</p>"),
        ("Does Cellar bundle Apple's D3DMetal?",
         "<p>No, and deliberately. D3DMetal comes under Apple's non-commercial terms, so Cellar "
         "never redistributes it: it is grafted into a runner on your own machine, at run time, "
         "from components already there. The same rule covers the store icons in the app: they are "
         "borrowed from the copies already on your Mac, or drawn in code — never shipped as logo "
         "files.</p>"),
        (f"Is Cellar affiliated with {', '.join(OWNERS[k] for k in OFFERED)} or Apple?",
         "<p>No. Cellar is an independent project. Store and product names appear only to say where "
         "a game came from.</p>"),
        ("What licence is it under?",
         f"<p>GPL-3.0. The source, the profile database and this site all live in the "
         f"<a href=\"{REPO}\">repository</a>.</p>"),
    ]),
]


def qa_html(question, answer):
    # <details> rather than JS: keyboard-operable, findable by the browser's own search, and it
    # still reads correctly with scripting off. The FAQ's prose is authored HTML in this file; the
    # question text is escaped like everything else.
    return (f'<details class="qa" id="{slugify(question)}"><summary>{html.escape(question)}</summary>'
            f'<div class="a">{answer}</div></details>')


FAQ_JS = """
(function(){
  // A link to one answer opens it, whether it arrives with the page or from a click later.
  function openHash(){var id=decodeURIComponent(location.hash.slice(1)); if(!id) return;
    var el=document.getElementById(id); if(el&&el.tagName==='DETAILS'){el.open=true;}}
  window.addEventListener('hashchange',openHash); openHash();
})();
"""


def render_faq(games, release):
    toc = "".join(f'<li><a href="#{anchor}">{html.escape(title)}</a></li>'
                  for title, anchor, _lede, _questions in FAQ_SECTIONS)
    sections = "\n".join(
        f'''<section class="faq-section" id="{anchor}" aria-labelledby="{anchor}-h">
      <h2 id="{anchor}-h">{html.escape(title)}</h2>
      <p class="lede">{html.escape(lede)}</p>
      {"".join(qa_html(q, a) for q, a in questions)}
    </section>''' for title, anchor, lede, questions in FAQ_SECTIONS)
    return f'''{head("Questions & answers — Cellar",
                 "How Cellar runs Windows games on an Apple Silicon Mac: what it needs, why it asks "
                 "you to sign in, what the compatibility ratings mean, and what to do when a game "
                 "will not start.", "faq.html")}
{topbar("faq", release)}
<main id="main">
<div class="page-head"><div class="wrap">
  <h1>Questions &amp; answers</h1>
  <p>How Cellar works, why it asks what it asks, and what to do when a game won&rsquo;t start.</p>
</div></div>
<div class="wrap faq-layout">
  <nav class="toc" aria-labelledby="toc-h"><h2 id="toc-h">On this page</h2><ol>{toc}</ol></nav>
  <div class="qa-list">
    {sections}
    <div class="callout"><h3>Still stuck?</h3>
      <p>Open an issue on <a href="{REPO}/issues">GitHub</a> with your Mac, your macOS version, the
      game, and the log from the run that failed — that is usually enough to spot it. Or browse the
      <a href="games.html">{len(games)} games Cellar knows</a>.</p></div>
  </div>
</div>
{closing_band(release)}
</main>
{site_footer(games)}
{scripts(THEME_JS, FAQ_JS)}
</body></html>
'''


def render_games(games, release):
    playable = sum(1 for g in games if g["status"] == "playable")
    return f'''{head("Games — Cellar",
                 f"The {len(games)} Windows games Cellar knows how to set up on a Mac, and what is "
                 "known about each: playable, experimental or untested.", "games.html")}
{topbar("games", release)}
<main id="main">
<div class="page-head"><div class="wrap">
  <h1>Games</h1>
  <p>{len(games)} Windows games Cellar knows how to set up, {playable} of them confirmed playable.
  Each card says exactly what is known about the game, and nothing more. A game that isn&rsquo;t
  here may still run — this is what has been written down, not the limit.</p>
</div></div>
<div class="wrap">
  <section class="block games-page" id="games" aria-labelledby="all-h">
    <h2 class="sr-only" id="all-h">All games</h2>
    {games_block(games)}
    {DONT_SEE}
  </section>
</div>
{closing_band(release)}
</main>
{site_footer(games)}
{scripts(THEME_JS, GAMES_JS)}
</body></html>
'''


def render_404(games, release):
    base = SITE_PATH
    return f'''{head("Page not found — Cellar", "This page does not exist on the Cellar site.",
                 "404.html", base)}
{topbar("", release, base)}
<main id="main" class="wrap notfound">
  <h1>This page isn&rsquo;t here.</h1>
  <p>It may have moved, or the link may be mistyped. Everything on the site is one click from the
  home page.</p>
  <div class="ctas">
    <a class="btn btn-primary" href="{base}index.html">Go to the home page</a>
    <a class="btn btn-ghost" href="{base}faq.html">Questions &amp; answers</a>
  </div>
</main>
{site_footer(games, base)}
{scripts(THEME_JS)}
</body></html>
'''


def write(name, text):
    with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main():
    games = load_games()
    release = latest_release()
    os.makedirs(OUT, exist_ok=True)
    # Ship the app icon as the site favicon + hero image.
    icon_png = os.path.join(ROOT, "app", "Resources", "AppIcon.png")
    if not os.path.exists(icon_png):
        sys.exit("error: app/Resources/AppIcon.png is missing; the site uses it as its icon")
    shutil.copyfile(icon_png, os.path.join(OUT, "icon.png"))
    media_out = os.path.join(OUT, "media")
    if os.path.isdir(media_out):
        shutil.rmtree(media_out)
    used = find_media()
    if used:
        os.makedirs(media_out)
        files = [v[0] for k, v in used.items() if k != TOUR_VIDEO[0]]
        if TOUR_VIDEO[0] in used:
            v = used[TOUR_VIDEO[0]]
            files += [v["src"], v["captions"], v["poster"][0]]
        for file in files:
            shutil.copyfile(os.path.join(MEDIA, file), os.path.join(media_out, file))
    write("index.html", render_index(games, release))
    write("games.html", render_games(games, release))
    write("faq.html", render_faq(games, release))
    write("404.html", render_404(games, release))
    write("robots.txt", f"User-agent: *\nAllow: /\nSitemap: {SITE_URL}sitemap.xml\n")
    write("sitemap.xml",
          '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
          f"  <url><loc>{SITE_URL}</loc></url>\n"
          f"  <url><loc>{SITE_URL}games.html</loc></url>\n"
          f"  <url><loc>{SITE_URL}faq.html</loc></url>\n"
          "</urlset>\n")
    write(".nojekyll", "")
    answers = sum(len(questions) for _t, _a, _l, questions in FAQ_SECTIONS)
    parser = "fallback parser" if tomllib is None or os.environ.get("CELLAR_TOML_FALLBACK") == "1" else "tomllib"
    print(f"Wrote {OUT}/index.html — {len(games)} games ({parser})")
    print(f"Wrote {OUT}/games.html — {len(games)} games")
    print(f"Wrote {OUT}/faq.html — {len(FAQ_SECTIONS)} sections, {answers} answers")
    print("Download: " + (f"{release['version']} → {release['url']}" if release
                          else f"{RELEASES}/latest (no release resolved)"))


if __name__ == "__main__":
    main()
