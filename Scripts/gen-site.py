#!/usr/bin/env python3
"""Generate the static Cellar site from profiles/*.toml into site/.

Pages: index.html (landing page + supported games), faq.html, 404.html, plus sitemap.xml and
robots.txt. Data-driven: every game card comes from a profile, so the page can't drift from what
Cellar supports, and the Download button names the real installer of the latest release.

Run: python3 Scripts/gen-site.py

Environment (all optional):
  CELLAR_SITE_OUT        write somewhere other than site/
  CELLAR_SITE_OFFLINE=1  skip the latest-release lookup (the button then opens the releases page)
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
OUT = os.environ.get("CELLAR_SITE_OUT") or os.path.join(ROOT, "site")
OWNER_REPO = "Echarnus/Cellar"
REPO = f"https://github.com/{OWNER_REPO}"
RELEASES = f"{REPO}/releases"
SITE_URL = "https://echarnus.github.io/Cellar/"
# Where the site lives on its host. Only 404.html needs it: GitHub Pages serves that page for any
# missing path, at any depth, so its links cannot be relative.
SITE_PATH = "/Cellar/"
MIN_MACOS = "13"  # LSMinimumSystemVersion in Scripts/package.sh

STORES = {  # profile store → how the site labels it
    "steam": "Steam",
    "battlenet": "Battle.net",
    "gog": "GOG",
}

STATUS = {  # profile status → (label, css class, what it means)
    "playable": ("Playable", "ok", "Someone ran it on named hardware; the profile says which Mac."),
    "experimental": ("Experimental", "warn", "It runs, with caveats worth reading first."),
    "untested": ("Untested", "muted", "The profile exists; nobody has confirmed it yet."),
}

# Profile DRM slugs that read badly as-is. Anything else is shown exactly as the profile says it.
DRM_LABELS = {"denuvo-anti-tamper": "Denuvo Anti-Tamper"}

# ---------------------------------------------------------------------------------------------
# Palette. One table, two uses: the CSS custom properties below are written from it, and
# Scripts/check-site.py measures CONTRAST against it, so a colour change that drops a pair under
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
             + "".join(f"--badge-{k}:{v};" for k, v in BADGES.items()) + "}\n")

# One stylesheet for every page, inlined — no build step, no extra request. A plain string (single
# braces), interpolated into the page f-strings.
CSS = THEME_CSS + """
*{box-sizing:border-box}
html{scroll-behavior:smooth;-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--fg);
  font:17px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Roboto,"Helvetica Neue",sans-serif;
  -webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}
img,svg{max-width:100%}
a{color:var(--link);text-underline-offset:.18em}
a:hover{text-decoration-thickness:2px}
:focus-visible{outline:3px solid var(--focus);outline-offset:3px;border-radius:8px}
h1,h2,h3{line-height:1.15;letter-spacing:-.022em;margin:0}
p{margin:0 0 1em}
code{font:.86em/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--surface-2);
  padding:2px 6px;border-radius:6px;overflow-wrap:anywhere}
.wrap{max-width:1120px;margin:0 auto;padding:0 20px}
.sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
.skip{position:absolute;left:12px;top:-60px;z-index:20;background:var(--surface);color:var(--fg);
  padding:12px 18px;border-radius:10px;border:1px solid var(--line);font-weight:600}
.skip:focus{top:12px}

/* Top bar */
.top{position:sticky;top:0;z-index:10;background:color-mix(in srgb,var(--bg) 86%,transparent);
  -webkit-backdrop-filter:saturate(180%) blur(14px);backdrop-filter:saturate(180%) blur(14px);
  border-bottom:1px solid var(--line)}
@supports not (background:color-mix(in srgb,red 50%,blue)){.top{background:var(--bg)}}
.top .wrap{display:flex;align-items:center;gap:8px;min-height:60px;flex-wrap:wrap}
.brand{display:inline-flex;align-items:center;gap:10px;color:var(--fg);text-decoration:none;
  font-weight:750;font-size:1.08rem;margin-right:auto;min-height:44px}
.brand img{width:30px;height:30px;border-radius:7px}
.nav{display:flex;gap:2px;order:3;width:100%;overflow-x:auto;margin:0 -8px;padding:0 0 6px;scrollbar-width:none}
.nav::-webkit-scrollbar{display:none}
.nav a{color:var(--muted);text-decoration:none;padding:0 12px;border-radius:9px;font-size:.95rem;
  min-height:44px;display:inline-flex;align-items:center;white-space:nowrap}
.nav a:hover{color:var(--fg);background:var(--surface-2)}
.nav a[aria-current=page]{color:var(--fg);font-weight:600}
@media (min-width:760px){.nav{order:0;width:auto;margin:0 6px 0 0;padding:0;overflow:visible}}
.icon-btn{display:inline-grid;place-items:center;width:44px;height:44px;border-radius:11px;
  border:1px solid var(--line);background:var(--surface);color:var(--fg);cursor:pointer}
.icon-btn:hover{background:var(--surface-2)}
.icon-btn svg{width:20px;height:20px}
.icon-btn .moon{display:none}
:root[data-theme=dark] .icon-btn .sun{display:none}
:root[data-theme=dark] .icon-btn .moon{display:block}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]) .icon-btn .sun{display:none}
  :root:not([data-theme=light]) .icon-btn .moon{display:block}}
.no-js .icon-btn{display:none}

/* Buttons */
.btn{display:inline-flex;align-items:center;justify-content:center;gap:10px;min-height:44px;
  padding:10px 18px;border-radius:12px;font-weight:650;text-decoration:none;border:1px solid transparent;
  transition:transform .15s ease,box-shadow .15s ease,background-color .15s ease}
.btn svg{width:18px;height:18px;flex:none}
.btn-primary{background:var(--primary);color:var(--on-primary)}
.btn-primary:hover{box-shadow:0 8px 22px var(--shadow);transform:translateY(-1px)}
.btn-small{padding:8px 14px;font-size:.92rem}
.btn-light{background:#fff;color:#1c1a1d;box-shadow:0 12px 32px rgba(0,0,0,.28)}
.btn-light:hover{transform:translateY(-2px);box-shadow:0 18px 40px rgba(0,0,0,.34)}
.btn-ghost{color:#fff;border-color:rgba(255,255,255,.55)}
.btn-ghost:hover{background:rgba(255,255,255,.12)}
.btn-big{padding:14px 24px;font-size:1.05rem;border-radius:14px}
.btn-big .lines{display:flex;flex-direction:column;text-align:left;line-height:1.25}
.btn-big small{font-weight:500;font-size:.78rem;color:#4a454b}
.hero .btn:focus-visible,.band .btn:focus-visible,.hero a:focus-visible,.band a:focus-visible{outline-color:#fff}

/* Hero */
.hero{color:#fff;background:radial-gradient(120% 120% at 15% -10%,var(--hero-1) 0%,var(--hero-2) 45%,var(--hero-3) 100%);
  overflow:hidden}
.hero .wrap{display:grid;gap:44px;align-items:center;padding-top:64px;padding-bottom:72px}
@media (min-width:900px){.hero .wrap{grid-template-columns:1.05fr .95fr;padding-top:88px;padding-bottom:96px}}
.eyebrow{display:inline-flex;gap:8px;align-items:center;font-size:.85rem;font-weight:600;letter-spacing:.02em;
  background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.22);padding:5px 12px;border-radius:99px;margin-bottom:22px}
.hero h1{font-size:clamp(2.4rem,5.6vw,3.7rem);font-weight:800;letter-spacing:-.035em}
.hero .lede{font-size:clamp(1.08rem,2.1vw,1.25rem);max-width:36ch;margin:20px 0 30px;color:#fff}
.hero .ctas{display:flex;gap:12px;flex-wrap:wrap;align-items:center}
.hero .fine{margin:18px 0 0;font-size:.9rem;color:#fff}
.hero .fine a{color:#fff}
.shelf{position:relative;justify-self:center;width:min(100%,460px);aspect-ratio:1/1}
@media (max-width:600px){.shelf{display:none}}
.shelf .cover{position:absolute;width:44%;aspect-ratio:2/3;border-radius:14px;overflow:hidden;
  box-shadow:0 26px 60px rgba(0,0,0,.45);background:linear-gradient(160deg,#c4466e,#4a0f22)}
.shelf .cover img{width:100%;height:100%;object-fit:cover;display:block}
.shelf .c1{left:2%;top:14%;transform:rotate(-8deg)}
.shelf .c2{left:28%;top:2%;z-index:2;width:46%}
.shelf .c3{right:2%;top:14%;transform:rotate(8deg)}
/* The icon sits under the covers, not on them, so it never hides a game's title. Its PNG carries
   macOS's transparent margin and its own rounded tile: the shadow follows the tile (drop-shadow),
   and height:auto keeps it square — the height attribute alone would pin it at 256px tall. */
.shelf .appicon{position:absolute;z-index:3;left:50%;bottom:0;transform:translateX(-50%);width:24%;height:auto;
  aspect-ratio:1/1;filter:drop-shadow(0 14px 22px rgba(0,0,0,.45))}
.page-head{color:#fff;background:radial-gradient(120% 140% at 15% -20%,var(--hero-1) 0%,var(--hero-2) 50%,var(--hero-3) 100%)}
.page-head .wrap{padding-top:56px;padding-bottom:56px}
.page-head h1{font-size:clamp(2.1rem,5vw,3rem);font-weight:800}
.page-head p{margin:14px 0 0;max-width:56ch;font-size:1.12rem;color:#fff}

/* Sections */
section.block{padding:84px 0 0}
.section-head{max-width:680px;margin-bottom:34px}
.kicker{color:var(--link);font-weight:700;font-size:.85rem;letter-spacing:.06em;text-transform:uppercase;margin:0 0 10px}
.section-head h2{font-size:clamp(1.8rem,3.6vw,2.5rem)}
.section-head p{color:var(--muted);font-size:1.08rem;margin:14px 0 0}
.stats{display:grid;grid-template-columns:repeat(2,1fr);gap:1px;background:var(--line);border:1px solid var(--line);
  border-radius:18px;overflow:hidden;margin:-36px 0 0;position:relative}
@media (min-width:760px){.stats{grid-template-columns:repeat(4,1fr)}}
.stats div{background:var(--surface);padding:18px 20px}
.stats b{display:block;font-size:1.6rem;letter-spacing:-.02em}
.stats span{color:var(--muted);font-size:.92rem}

.features{display:grid;gap:18px;grid-template-columns:repeat(auto-fit,minmax(min(100%,290px),1fr));list-style:none;margin:0;padding:0}
.feature{background:var(--surface);border:1px solid var(--line);border-radius:18px;padding:24px}
.feature .ic{width:44px;height:44px;border-radius:12px;display:grid;place-items:center;background:var(--surface-2);color:var(--link);margin-bottom:16px}
.feature .ic svg{width:24px;height:24px}
.feature h3{font-size:1.15rem;margin-bottom:8px}
.feature p{color:var(--muted);margin:0}

.steps{display:grid;gap:18px;grid-template-columns:repeat(auto-fit,minmax(min(100%,260px),1fr));list-style:none;margin:0;padding:0;counter-reset:step}
.steps li{position:relative;background:var(--surface);border:1px solid var(--line);border-radius:18px;padding:24px 24px 24px 76px;counter-increment:step}
.steps li::before{content:counter(step);position:absolute;left:24px;top:22px;width:36px;height:36px;border-radius:50%;
  background:var(--primary);color:var(--on-primary);display:grid;place-items:center;font-weight:750}
.steps h3{font-size:1.1rem;margin-bottom:6px}
.steps p{margin:0;color:var(--muted)}

/* Games */
.toolbar{display:flex;flex-wrap:wrap;gap:12px 16px;align-items:center;margin:0 0 22px}
.no-js .toolbar{display:none}
.search{position:relative;flex:1 1 240px;max-width:360px}
.search svg{position:absolute;left:13px;top:50%;width:18px;height:18px;transform:translateY(-50%);color:var(--muted);pointer-events:none}
.search input{width:100%;min-height:44px;padding:10px 14px 10px 40px;border-radius:12px;border:1px solid var(--muted);
  background:var(--surface);color:var(--fg);font:inherit;font-size:1rem}
.seg{display:inline-flex;flex-wrap:wrap;gap:4px;padding:4px;border-radius:13px;background:var(--surface-2);border:1px solid var(--line)}
.seg button{min-height:38px;padding:6px 13px;border:0;border-radius:9px;background:transparent;color:var(--fg);
  font:inherit;font-size:.93rem;cursor:pointer}
.seg button:hover{background:var(--surface)}
.seg button[aria-pressed=true]{background:var(--surface);font-weight:650;box-shadow:0 1px 3px var(--shadow),inset 0 0 0 1px var(--line)}
.seg .n{color:var(--muted);font-weight:500;margin-left:4px}
.count{color:var(--muted);font-size:.95rem;margin:0 0 16px}
.grid{display:grid;gap:20px;grid-template-columns:repeat(auto-fill,minmax(min(100%,230px),1fr));list-style:none;margin:0;padding:0}
.card{display:flex;flex-direction:column;background:var(--surface);border:1px solid var(--line);border-radius:18px;overflow:hidden;
  transition:transform .18s ease,box-shadow .18s ease}
.card:hover{transform:translateY(-3px);box-shadow:0 18px 36px var(--shadow)}
.card[hidden]{display:none}
.card .art{position:relative;aspect-ratio:2/3;background:linear-gradient(160deg,var(--hero-1),var(--hero-3));color:#fff}
.card .art .ph{position:absolute;inset:0;display:grid;place-items:center;padding:18px;text-align:center;font-weight:750;font-size:1.25rem;line-height:1.2}
.card .art img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;display:block}
.card .art img.broken{display:none}
.badge{position:absolute;top:10px;left:10px;display:inline-flex;align-items:center;gap:5px;color:#fff;font-size:.78rem;
  font-weight:700;padding:4px 10px 4px 8px;border-radius:99px;background:var(--badge-muted);box-shadow:0 2px 8px rgba(0,0,0,.3)}
.badge svg{width:14px;height:14px}
.badge.ok{background:var(--badge-ok)}.badge.warn{background:var(--badge-warn)}
.card .meta{padding:16px 16px 18px;display:flex;flex-direction:column;gap:10px;flex:1}
/* On a phone, a row per game: a full-width 2:3 cover would make the list ten screens long. */
@media (max-width:540px){.card{flex-direction:row}.card .art{width:108px;flex:none;aspect-ratio:auto;min-height:162px}
  .card .art .ph{font-size:.85rem;padding:8px}.badge{top:6px;left:6px;font-size:.7rem;padding:3px 7px 3px 5px}
  .card .meta{padding:12px 14px}}
.card h3{font-size:1.06rem;line-height:1.25}
.chip{display:inline-block;font-size:.8rem;font-weight:650;padding:3px 10px;border-radius:7px}
.chip.steam{color:var(--steam);background:var(--steam-bg)}
.chip.battlenet{color:var(--battlenet);background:var(--battlenet-bg)}
.chip.gog{color:var(--gog);background:var(--gog-bg)}
.facts{margin:0;display:grid;grid-template-columns:auto 1fr;gap:4px 12px;font-size:.88rem}
.facts dt{color:var(--muted)}
.facts dd{margin:0;overflow-wrap:anywhere}
.card .more{margin-top:auto;font-size:.88rem;font-weight:600;min-height:44px;display:inline-flex;align-items:center}
.empty{text-align:center;color:var(--muted);padding:40px 0}
.legend{display:grid;gap:12px;grid-template-columns:repeat(auto-fit,minmax(min(100%,250px),1fr));margin:28px 0 0;padding:0;list-style:none}
.legend li{display:flex;gap:10px;align-items:flex-start;color:var(--muted);font-size:.93rem}
.legend b{color:var(--fg)}
.legend svg{width:18px;height:18px;flex:none;margin-top:3px}
.legend .ok{color:var(--ok)}.legend .warn{color:var(--warn)}.legend .muted{color:var(--untested)}
.callout{margin:28px 0 0;background:var(--surface);border:1px solid var(--line);border-left:4px solid var(--primary);border-radius:14px;padding:18px 22px}
.callout h3{font-size:1.05rem;margin-bottom:4px}
.callout p{margin:0;color:var(--muted)}

/* Requirements */
.reqs{display:grid;gap:16px;grid-template-columns:repeat(auto-fit,minmax(min(100%,240px),1fr));list-style:none;margin:0;padding:0}
.reqs li{background:var(--surface);border:1px solid var(--line);border-radius:16px;padding:20px}
.reqs b{display:block;font-size:1.05rem;margin-bottom:4px}
.reqs span{color:var(--muted)}

/* FAQ */
.qa-list{max-width:820px}
details.qa{background:var(--surface);border:1px solid var(--line);border-radius:14px;margin:10px 0;scroll-margin-top:84px}
details.qa>summary{cursor:pointer;list-style:none;padding:14px 18px;font-weight:650;display:flex;gap:14px;align-items:center;min-height:52px;border-radius:14px}
details.qa>summary::-webkit-details-marker{display:none}
details.qa>summary::after{content:"";flex:none;margin-left:auto;width:9px;height:9px;border-right:2px solid var(--muted);border-bottom:2px solid var(--muted);
  transform:rotate(45deg) translate(-2px,-2px);transition:transform .2s ease}
details.qa[open]>summary::after{transform:rotate(225deg) translate(-2px,-2px)}
details.qa[open]>summary{border-bottom:1px solid var(--line);border-radius:14px 14px 0 0}
details.qa .a{padding:16px 18px 4px}
details.qa .a p,details.qa .a ul{margin:0 0 14px}
details.qa .a ul{padding-left:20px}
details.qa .a li{margin:5px 0}
.faq-layout{display:grid;gap:36px;padding:44px 0 0}
@media (min-width:960px){.faq-layout{grid-template-columns:240px 1fr}}
.toc{align-self:start}
@media (min-width:960px){.toc{position:sticky;top:84px}}
.toc h2{font-size:.85rem;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);margin:0 0 8px}
.toc ol{list-style:none;margin:0;padding:0;display:flex;flex-wrap:wrap;gap:4px}
@media (min-width:960px){.toc ol{flex-direction:column}}
.toc a{display:inline-flex;align-items:center;min-height:40px;padding:0 12px;border-radius:9px;color:var(--fg);text-decoration:none;
  background:var(--surface-2)}
@media (min-width:960px){.toc a{background:none;display:flex}}
.toc a:hover{background:var(--surface-2)}
.faq-section{margin:0 0 44px;scroll-margin-top:84px}
.faq-section h2{font-size:1.55rem}
.faq-section .lede{color:var(--muted);margin:6px 0 14px}
.more-link{display:inline-flex;align-items:center;min-height:44px;font-weight:650}

/* Closing band + footer */
.band{margin:96px 0 0;color:#fff;background:radial-gradient(120% 160% at 85% 120%,var(--hero-1) 0%,var(--hero-2) 50%,var(--hero-3) 100%)}
.band .wrap{padding-top:64px;padding-bottom:64px;display:flex;flex-wrap:wrap;gap:24px;align-items:center;justify-content:space-between}
.band h2{font-size:clamp(1.7rem,3.4vw,2.3rem)}
.band p{margin:10px 0 0;color:#fff;max-width:48ch}
footer.site{border-top:1px solid var(--line);padding:48px 0 56px;color:var(--muted);font-size:.93rem}
footer.site .cols{display:grid;gap:28px;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));margin-bottom:32px}
footer.site h2{font-size:.85rem;text-transform:uppercase;letter-spacing:.06em;color:var(--fg);margin:0 0 8px}
footer.site ul{list-style:none;margin:0;padding:0}
footer.site li a{display:inline-flex;align-items:center;min-height:36px;color:var(--muted);text-decoration:none}
footer.site li a:hover{color:var(--fg);text-decoration:underline}
footer.site .legal{max-width:80ch;margin:0}
.notfound{padding:96px 0 40px;text-align:center}
.notfound h1{font-size:clamp(2rem,5vw,3rem);margin-bottom:12px}
.notfound p{color:var(--muted)}
.notfound .ctas{display:flex;gap:12px;justify-content:center;flex-wrap:wrap;margin-top:24px}
.notfound .btn-ghost{color:var(--fg);border-color:var(--line)}

@media (prefers-reduced-motion:reduce){html{scroll-behavior:auto}*,*::before,*::after{animation:none!important;transition:none!important}
  .card:hover,.btn:hover{transform:none}}
@media (prefers-contrast:more){:root{--line:var(--muted)}.seg button[aria-pressed=true]{outline:2px solid var(--fg)}}
@media print{.top,.toolbar,.band{display:none}body{background:#fff;color:#000}}
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
  function apply(){
    var term=(q.value||'').trim().toLowerCase(), shown=0;
    cards.forEach(function(c){
      var ok=(!term||c.dataset.name.indexOf(term)>=0)
        &&(state.store==='all'||c.dataset.store===state.store)
        &&(state.status==='all'||c.dataset.status===state.status);
      c.hidden=!ok; if(ok) shown++;});
    count.textContent=shown===cards.length? 'Showing all '+cards.length+' games'
      : 'Showing '+shown+' of '+cards.length+' games';
    empty.hidden=shown>0;}
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
        # `needs_live_steam` is the original spelling of `needs_live_session`; both still read.
        needs_client = comp.get("needs_live_session", comp.get("needs_live_steam", True))
        drm = str(comp.get("drm", "")).strip()
        games.append({
            "name": str(g["name"]),
            "slug": str(g["slug"]),
            "api": str(g.get("graphics_api", "")).strip(),
            "drm": DRM_LABELS.get(drm, drm),
            "status": status,
            "store": storekey,
            "client": bool(needs_client),
            "portrait": str(portrait),
            "profile": f"profiles/{os.path.basename(path)}",
        })
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
    return {
        "version": version,
        "url": str(dmg["browser_download_url"]),
        "size": f"{dmg.get('size', 0) / 1_000_000:.1f} MB",
        "notes": str(rel.get("html_url") or f"{RELEASES}/latest"),
        "date": str(rel.get("published_at", ""))[:10],
    }


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
             (f"{base}index.html#games", "Games", None),
             (f"{base}faq.html", "FAQ", "faq"),
             (REPO, "GitHub", None)]
    current_mark = ' aria-current="page"'
    links = "".join(
        f'<a href="{n(href)}"{current_mark if key and key == current else ""}>{label}</a>'
        for href, label, key in pages)
    return f'''<header class="top"><div class="wrap">
  <a class="brand" href="{base}index.html"><img src="{base}icon.png" alt="" width="30" height="30">Cellar</a>
  <nav class="nav" aria-label="Main">{links}</nav>
  <button class="icon-btn" id="theme" type="button" aria-pressed="false" aria-label="Switch to dark mode">{icon("sun", "sun")}{icon("moon", "moon")}</button>
  <a class="btn btn-primary btn-small" href="{n(download_href(release))}">{icon("download")}Download</a>
</div></header>'''


def download_href(release):
    return release["url"] if release else f"{RELEASES}/latest"


def download_detail(release):
    bits = ([f"Version {release['version']}", release["size"]] if release else []) + \
           [f"Apple Silicon · macOS {MIN_MACOS} or later"]
    return " · ".join(bits)


def closing_band(release, base=""):
    n = html.escape
    return f'''<section class="band" aria-labelledby="band-h"><div class="wrap">
  <div>
    <h2 id="band-h">Bring your library over.</h2>
    <p>Download Cellar, sign in to the stores you already use, and play the games you own.</p>
  </div>
  <a class="btn btn-light btn-big" href="{n(download_href(release))}">{icon("download")}<span class="lines">Download for Mac<small>{n(download_detail(release))}</small></span></a>
</div></section>'''


def site_footer(games, base=""):
    playable = sum(1 for g in games if g["status"] == "playable")
    return f'''<footer class="site"><div class="wrap">
  <div class="cols">
    <div><h2>Cellar</h2><ul>
      <li><a href="{RELEASES}/latest">Download</a></li>
      <li><a href="{RELEASES}">All releases</a></li>
      <li><a href="{base}index.html#features">Features</a></li>
      <li><a href="{base}index.html#games">Supported games</a></li>
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
  <p class="legal">{len(games)} profiled games, {playable} confirmed playable. Cellar is free software
  under GPL-3.0 and is not affiliated with Apple, Valve, Blizzard, GOG, CodeWeavers or any game
  publisher; their names appear only to say where a game comes from. Built on
  <a href="https://www.winehq.org/">Wine</a>, the Windows compatibility layer — Cellar is a launcher
  over it, and the hard part is theirs.</p>
</div></footer>'''


def scripts(*bodies):
    return "".join(f"<script>{b}</script>" for b in bodies)


# ---------------------------------------------------------------------------------------------
# Landing page
# ---------------------------------------------------------------------------------------------
FEATURES = [
    ("play", "One click from download to playing",
     "Cellar fetches the Wine runner, sets up the graphics layer and builds a bottle for each game. "
     "No Terminal, no Windows licence, no virtual machine."),
    ("stores", "Your stores, your library",
     "Steam, Battle.net and GOG. Sign in once per store, not once per game, and Cellar shows the "
     "games you own there."),
    ("chip", "Apple's D3DMetal, or DXVK",
     "Direct3D is translated to Metal on the Apple GPU. Every game names a fallback backend for "
     "when the first choice misbehaves."),
    ("profile", "A profile for every game",
     "The fixes a game needs are written down once and reused forever, in an open database "
     "anyone can add to."),
    ("gauge", "See what limits your frame rate",
     "Turn on the Metal performance overlay in Settings, or measure a session with "
     "<code>cellar perf measure</code>."),
    ("shield", "Free, open and private",
     "GPL-3.0, no Cellar account, no telemetry. Games come from your own accounts, and their DRM "
     "runs untouched."),
]

STEPS = [
    ("Install Cellar", "Open the download and drag Cellar to Applications. It sets up what it needs the "
     "first time a game asks for it."),
    ("Sign in to your stores", "Steam, Battle.net or GOG, with your own account. Once per store; you can "
     "also skip it and do it later."),
    ("Pick a game and play", "Choose a game you own, install it, and press Play. Cellar picks the runner "
     "and backend from the game's profile."),
]


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
    dl = "".join(f"<dt>{k}</dt><dd>{v}</dd>" for k, v in facts)
    return f'''
    <li class="card" data-name="{n(g['name'].lower())}" data-status="{n(g['status'])}" data-store="{n(g['store'])}">
      <div class="art"><span class="ph" aria-hidden="true">{n(g['name'])}</span>{art}<span class="badge {cls}">{icon(cls)}{n(label)}</span></div>
      <div class="meta">
        <h3>{n(g['name'])}</h3>
        <div><span class="chip {n(g['store'])}">{n(store)}</span></div>
        <dl class="facts">{dl}</dl>
        <a class="more" href="{REPO}/blob/main/{n(g['profile'])}">Read the profile<span class="sr-only"> for {n(g['name'])}</span></a>
      </div>
    </li>'''


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
    playable = sum(1 for g in games if g["status"] == "playable")
    stores_present = [k for k in STORES if any(g["store"] == k for g in games)]
    statuses_present = [k for k in STATUS if any(g["status"] == k for g in games)]
    store_opts = [("all", "All stores", total)] + [
        (k, STORES[k], sum(1 for g in games if g["store"] == k)) for k in stores_present]
    status_opts = [("all", "Any status", total)] + [
        (k, STATUS[k][0], sum(1 for g in games if g["status"] == k)) for k in statuses_present]

    covers = [g for g in games if g["portrait"]][:3]
    shelf = "".join(
        f'<div class="cover c{i + 1}"><img src="{n(g["portrait"])}" alt="" width="600" height="900"'
        f' onerror="this.remove()"></div>' for i, g in enumerate(covers))

    features = "".join(
        f'<li class="feature"><div class="ic">{icon(ic)}</div><h3>{title}</h3><p>{body}</p></li>'
        for ic, title, body in FEATURES)
    steps = "".join(f"<li><h3>{title}</h3><p>{body}</p></li>" for title, body in STEPS)
    cards = "".join(card(g) for g in games)
    legend = "".join(
        f'<li>{icon(cls, cls)}<span><b>{label}</b> — {meaning}</span></li>'
        for _k, (label, cls, meaning) in STATUS.items())

    teaser_ids = ["what-is-cellar", "which-macs-does-it-work-on",
                  "macos-says-cellar-can-t-be-opened", "what-about-games-with-anti-cheat"]
    teaser = "".join(qa_html(q, a) for _t, _anchor, _l, qs in FAQ_SECTIONS for q, a in qs
                     if slugify(q) in teaser_ids)

    release_line = (f'Version {n(release["version"])} · <a href="{n(release["notes"])}">what&rsquo;s new</a>'
                    if release else f'<a href="{RELEASES}">All releases</a>')
    ld = json.dumps({
        "@context": "https://schema.org", "@type": "SoftwareApplication", "name": "Cellar",
        "operatingSystem": f"macOS {MIN_MACOS} or later (Apple Silicon)",
        "applicationCategory": "GameApplication", "url": SITE_URL,
        "downloadUrl": download_href(release), "license": "https://www.gnu.org/licenses/gpl-3.0.html",
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        **({"softwareVersion": release["version"]} if release else {}),
    }).replace("<", "\\u003c")

    return f'''{head("Cellar — Windows games on your Mac",
                 "Cellar runs the Windows games you own on Apple Silicon Macs: Wine with Apple's "
                 "D3DMetal, per-game profiles, and your own Steam, Battle.net and GOG accounts. "
                 "Free and open source.", "index.html")}
{topbar("home", release)}
<main id="main">
<section class="hero" aria-labelledby="hero-h"><div class="wrap">
  <div>
    <p class="eyebrow">Free and open source · For Apple Silicon</p>
    <h1 id="hero-h">Your Windows games, on your Mac.</h1>
    <p class="lede">Cellar runs the Windows games you already own on Apple Silicon. It sets up Wine and
    Apple&rsquo;s D3DMetal for each game, signs in to your stores once, and gets out of the way.</p>
    <div class="ctas">
      <a class="btn btn-light btn-big" href="{n(download_href(release))}">{icon("download")}<span class="lines">Download for Mac<small>{n(download_detail(release))}</small></span></a>
      <a class="btn btn-ghost btn-big" href="#games">See supported games</a>
    </div>
    <p class="fine">{release_line} · Early builds aren&rsquo;t notarised yet:
    <a href="faq.html#macos-says-cellar-can-t-be-opened">how to open Cellar the first time</a></p>
  </div>
  <div class="shelf" aria-hidden="true">{shelf}<img class="appicon" src="icon.png" alt="" width="256" height="256"></div>
</div></section>

<div class="wrap">
  <dl class="stats">
    <div><dt class="sr-only">Game profiles</dt><dd style="margin:0"><b>{total}</b><span>game profiles</span></dd></div>
    <div><dt class="sr-only">Confirmed playable</dt><dd style="margin:0"><b>{playable}</b><span>confirmed playable</span></dd></div>
    <div><dt class="sr-only">Stores</dt><dd style="margin:0"><b>{len(STORES)}</b><span>stores: {", ".join(STORES.values())}</span></dd></div>
    <div><dt class="sr-only">Price</dt><dd style="margin:0"><b>Free</b><span>GPL-3.0, no telemetry</span></dd></div>
  </dl>

  <section class="block" id="features" aria-labelledby="features-h">
    <div class="section-head"><p class="kicker">Features</p>
      <h2 id="features-h">Everything a game needs, set up for you.</h2>
      <p>Cellar is to the Mac what Proton is to Linux: the Windows game runs much as it does on a PC,
      and your Mac stays a Mac.</p></div>
    <ul class="features">{features}</ul>
  </section>

  <section class="block" id="how" aria-labelledby="how-h">
    <div class="section-head"><p class="kicker">How it works</p>
      <h2 id="how-h">Three steps, once.</h2></div>
    <ol class="steps">{steps}</ol>
  </section>

  <section class="block" id="games" aria-labelledby="games-h">
    <div class="section-head"><p class="kicker">Supported games</p>
      <h2 id="games-h">What has a profile today.</h2>
      <p>Every card comes straight from a profile in the repository, so this list can&rsquo;t claim more
      than the profile does. A game without one may still run — the list is what has been written
      down, not the limit.</p></div>
    <div class="toolbar" role="search" aria-label="Filter games">
      <div class="search">{icon("search")}<label class="sr-only" for="q">Search games</label>
        <input id="q" type="search" placeholder="Search games" autocomplete="off"></div>
      {seg("store", "Store", store_opts)}
      {seg("status", "Status", status_opts)}
    </div>
    <p class="count" id="count" role="status" aria-live="polite">Showing all {total} games</p>
    <ul class="grid" id="grid">{cards}
    </ul>
    <div class="empty" id="empty" hidden><p>No games match those filters.</p>
      <button class="btn btn-primary btn-small" id="reset" type="button">Show all games</button></div>
    <ul class="legend">{legend}</ul>
    <div class="callout"><h3>Don&rsquo;t see your game?</h3>
      <p>A game is one small profile file: its store, its executable and graphics API, and what you saw
      when you ran it. <a href="{REPO}/blob/main/CONTRIBUTING.md">Add one</a>, or read
      <a href="faq.html#games">how this list works</a>.</p></div>
  </section>

  <section class="block" id="requirements" aria-labelledby="req-h">
    <div class="section-head"><p class="kicker">Requirements</p>
      <h2 id="req-h">What your Mac needs.</h2>
      <p>Open Cellar, or run <code>cellar doctor</code>, and it tells you what is missing before
      anything fails.</p></div>
    <ul class="reqs">
      <li><b>Apple Silicon</b><span>M1 or later. Intel Macs are not supported.</span></li>
      <li><b>macOS {MIN_MACOS} or later</b><span>Tested most on macOS 26 Tahoe.</span></li>
      <li><b>Rosetta 2</b><span>Wine runs as an Intel app under Rosetta; macOS installs it on request.</span></li>
      <li><b>A game you own</b><span>On Steam, Battle.net or GOG, from your own account.</span></li>
    </ul>
  </section>

  <section class="block" id="faq" aria-labelledby="faq-h">
    <div class="section-head"><p class="kicker">Questions</p>
      <h2 id="faq-h">The ones people ask first.</h2></div>
    <div class="qa-list">{teaser}</div>
    <a class="more-link" href="faq.html">All questions and answers</a>
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
         "<p>Cellar runs <b>Windows games on Apple Silicon Macs</b>. For each game it builds a "
         "<i>bottle</i> — a small, self-contained Windows environment — from Wine plus a "
         "graphics-translation layer that turns the game's Direct3D calls into Metal. The game runs "
         "much as it does on a PC. Your Mac does not become one.</p>"
         "<p>It is the same idea as Valve's Proton on Linux, aimed at macOS, and it is free and "
         "open source under GPL-3.0.</p>"),
        ("Do I need a Windows licence, Boot Camp, or a virtual machine?",
         "<p>None of the three. Wine is not an emulator and not a virtual machine — it answers the "
         "Windows API calls a game makes, as it makes them. There is no Windows install to "
         "maintain and no licence to buy.</p>"),
        ("Which Macs does it work on?",
         f"<p><b>Apple Silicon only</b> (M1 and later), on macOS {MIN_MACOS} or newer; it is tested "
         "most on macOS 26 Tahoe. Cellar's Wine runners are x86 builds that run under Rosetta 2, "
         "with the graphics work handed to Metal on the Apple GPU — so an Intel Mac is out of "
         "scope.</p>"
         "<p>Open the app, or run <code>cellar doctor</code>, and it will tell you what your "
         "machine is missing rather than failing later for an unclear reason.</p>"),
        ("How do I install it?",
         "<p>Download the DMG, drag Cellar to Applications, and open it. On first launch it "
         "introduces itself, asks once for the folders where Windows games keep their saves, and "
         "offers to sign you in to your stores. You can skip signing in — Cellar still opens, and "
         "signing in later works identically from <b>Accounts</b> (⌘⇧A) or <b>Settings → Manage "
         "accounts</b>.</p>"
         "<p>Cellar downloads the Wine runner itself the first time a game needs one. No Terminal "
         "required, though there is a full <code>cellar</code> command-line tool if you prefer "
         "one.</p>"),
        ("macOS says Cellar can't be opened.",
         "<p>Early releases are not yet notarised by Apple, so the first time you open Cellar, macOS "
         "stops it. To allow it:</p>"
         "<ul><li>Open <b>System Settings → Privacy &amp; Security</b>.</li>"
         "<li>Scroll to the message saying Cellar was blocked, and click <b>Open Anyway</b>.</li>"
         "<li>Confirm with your password or Touch ID.</li></ul>"
         "<p>You only do this once; after that Cellar opens normally.</p>"),
        ("Is it free? Do I need an account with you?",
         "<p>Free, GPL-3.0, and there is no Cellar account, no sign-up and no telemetry. The only "
         "accounts involved are the game stores you already have.</p>"),
    ]),

    ("Accounts and signing in", "accounts",
     "Why Cellar asks, what it can see, and what it deliberately won't claim.", [
        ("Why do I have to sign in at all?",
         "<p>Because the games are <b>yours</b>. Cellar does not host or distribute game files — it "
         "installs from your own Steam, Battle.net or GOG account, the way those clients would on a "
         "PC. No sign-in, no library.</p>"),
        ("Once per store, or once per game?",
         "<p><b>Once per store.</b> One Steam sign-in covers your whole Steam library — both what "
         "you own and downloading it. GOG is one token Cellar holds for the account. That is why "
         "signing in lives on the <b>Accounts</b> screen — the person icon in the sidebar, ⌘⇧A, or "
         "Settings → Manage accounts — and not on each game's page.</p>"),
        ("Does Cellar see my password?",
         "<p>No. Steam's sign-in is Steam's own QR device flow: you approve it in the Steam mobile "
         "app. GOG uses its normal login page and hands back an OAuth token, which Cellar keeps in "
         "your macOS Keychain. Battle.net's sign-in happens entirely inside Blizzard's client.</p>"),
        ("Why does Battle.net say “Add” instead of “Sign in”?",
         "<p>Because Blizzard writes nothing readable that says who is signed in, or which games "
         "that account owns. Steam and GOG both answer those questions; Battle.net does not.</p>"
         "<p>So Accounts asks you once whether Battle.net is yours — <b>Add</b> — and Cellar then "
         "shows its games, saying plainly that it cannot check you own them. You sign in inside "
         "Blizzard's own window when you open it. Where Cellar looks oddly modest about what it "
         "knows, this is usually why.</p>"),
        ("Why does a Windows Steam run inside the bottle?",
         "<p>Cellar downloads Steam games with your one sign-in, without starting a Steam window. "
         "But many Steamworks games check for a <i>running</i> Steam while they play, so for those "
         "Cellar installs the Windows Steam client in the bottle and starts it beside the game. "
         "It is a dependency of the game, not a second account. Cards that say <b>Just the game</b> "
         "under While playing skip it: the game still comes from your Steam account, it just "
         "doesn't need Steam running to play.</p>"),
        ("Can I sign out?",
         "<p>Yes. Accounts offers Sign out for each session Cellar itself holds. The Steam client "
         "and Battle.net are signed out from inside their own windows, because that is where those "
         "sessions actually live.</p>"),
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
        ("My game isn't listed. Can I still play it?",
         "<p>Often, yes — the list is what has been <i>profiled</i>, not the limit of what works. A "
         "profile is a small text file naming the game's store, its AppID or install folder, its "
         "executable and graphics API, and which backend to use. Copy the closest existing one and "
         f"adjust it; see <a href=\"{REPO}/blob/main/CONTRIBUTING.md\">CONTRIBUTING.md</a>.</p>"
         "<p>Adding a profile is also how a game reaches this site: it is rebuilt from the profiles "
         "every time one changes.</p>"),
        ("What about games with anti-cheat?",
         "<p>Competitive games with kernel-level anti-cheat generally do not run, and Cellar will "
         "not make them. It <b>never circumvents DRM or anti-cheat</b> — protection runs through "
         "the translation layer untouched, exactly as the publisher shipped it. Where a profile "
         "knows of an anti-cheat problem it says so plainly, rather than letting you discover it "
         "after a 60&nbsp;GB download.</p>"),
        ("Does the store's client have to be running while I play?",
         "<p>It depends on the game, and its card says which. Steamworks titles usually want a live "
         "Steam session. GOG's games are DRM-free, so nothing needs to run beside them. Either "
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
         "works in places D3DMetal does not. Each profile names a backend and a fallback, so a game "
         "that misbehaves on one can be run on the other.</p>"),
        ("Can I see an FPS counter?",
         "<p>Yes — <b>Settings → Show Metal performance overlay (FPS)</b> adds an FPS and frametime "
         "HUD to games launched from Cellar. To measure a whole session and see what limits it, run "
         "<code>cellar perf measure &lt;game&gt;</code>.</p>"),
    ]),

    ("When something goes wrong", "trouble", "The usual causes, in the order worth checking.", [
        ("The first set-up is taking ages. Is it stuck?",
         "<p>Probably not. The first game downloads a Wine runner and builds a fresh bottle, which "
         "takes a few minutes on a good connection; later games reuse the runner and are much "
         "quicker. Cellar shows what it is running while it works — if the activity log is still "
         "moving, let it finish.</p>"),
        ("A store window opened and is waiting for me.",
         "<p>Expected, for Battle.net: Blizzard's installer has no silent mode, so its window "
         "genuinely needs a few clicks. Cellar warns you before opening one rather than appearing "
         "to hang and being force-quit. Steam's installer does run silently.</p>"),
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
         "library, and keeps a GOG sign-in in your login keychain. That command takes all of it, "
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
        ("Is Cellar affiliated with Valve, Blizzard, GOG or Apple?",
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
      <a href="index.html#games">{len(games)} profiled games</a>.</p></div>
  </div>
</div>
{closing_band(release)}
</main>
{site_footer(games)}
{scripts(THEME_JS, FAQ_JS)}
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
    icon_png = os.path.join(ROOT, "Resources", "AppIcon.png")
    if not os.path.exists(icon_png):
        sys.exit("error: Resources/AppIcon.png is missing; the site uses it as its icon")
    shutil.copyfile(icon_png, os.path.join(OUT, "icon.png"))
    write("index.html", render_index(games, release))
    write("faq.html", render_faq(games, release))
    write("404.html", render_404(games, release))
    write("robots.txt", f"User-agent: *\nAllow: /\nSitemap: {SITE_URL}sitemap.xml\n")
    write("sitemap.xml",
          '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
          f"  <url><loc>{SITE_URL}</loc></url>\n"
          f"  <url><loc>{SITE_URL}faq.html</loc></url>\n"
          "</urlset>\n")
    write(".nojekyll", "")
    answers = sum(len(questions) for _t, _a, _l, questions in FAQ_SECTIONS)
    parser = "fallback parser" if tomllib is None or os.environ.get("CELLAR_TOML_FALLBACK") == "1" else "tomllib"
    print(f"Wrote {OUT}/index.html — {len(games)} games ({parser})")
    print(f"Wrote {OUT}/faq.html — {len(FAQ_SECTIONS)} sections, {answers} answers")
    print("Download: " + (f"{release['version']} → {release['url']}" if release
                          else f"{RELEASES}/latest (no release resolved)"))


if __name__ == "__main__":
    main()
