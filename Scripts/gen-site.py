#!/usr/bin/env python3
"""Generate the static Cellar site (hero + games + FAQ) from profiles/*.toml into site/.

Data-driven: every game card comes from a profile, so the page can't drift from what Cellar
supports. Run: python3 Scripts/gen-site.py
"""
import glob
import html
import os
import shutil
import sys

try:
    import tomllib  # Python 3.11+

    def parse_toml(path):
        with open(path, "rb") as f:
            return tomllib.load(f)
except ModuleNotFoundError:
    import re

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

    def parse_toml(path):
        data, section = {}, None
        for raw in open(path, encoding="utf-8"):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            m = re.match(r"\[([^\]]+)\]$", line)
            if m:
                section = {}; data[m.group(1)] = section; continue
            if "=" in line and section is not None:
                k, v = line.split("=", 1)
                section[k.strip()] = _val(v)
        return data

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "site")
REPO = "https://github.com/Echarnus/Cellar"
DMG = f"{REPO}/releases/latest/download/Cellar.dmg"

STORES = {  # profile store → how the site labels it
    "steam": {"label": "Steam", "cls": "steam"},
    "battlenet": {"label": "Battle.net", "cls": "battlenet"},
    "gog": {"label": "GOG", "cls": "gog"},
    "standalone": {"label": "No store", "cls": "standalone"},
}

STATUS = {  # profile status → (label, css class)
    "playable": ("Playable", "ok"),
    "experimental": ("Experimental", "warn"),
    "untested": ("Untested", "muted"),
}

# One stylesheet for both pages, inlined into each — no build step, no extra request. Held as a
# plain string (single braces) and interpolated into the page f-strings, so it is written once
# rather than kept in step by hand.
CSS = """
  :root{color-scheme:light dark;
    --bg:#faf7f6;--fg:#1b1a1c;--card:#ffffff;--muted:#6c666b;--line:#eadfe0;
    --wine:#8e1f3d;--wine2:#5a1228;--accent:#0a84ff;--ok:#2fae55;--warn:#e0872a;}
  @media (prefers-color-scheme:dark){:root{
    --bg:#141013;--fg:#f3eef0;--card:#20191d;--muted:#9c949a;--line:#33272d;--accent:#4aa8ff;}}
  *{box-sizing:border-box}
  html{scroll-behavior:smooth}
  body{margin:0;background:var(--bg);color:var(--fg);
    font:16px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Roboto,sans-serif;
    -webkit-font-smoothing:antialiased}
  a{color:var(--accent);text-decoration:none}
  a:hover{text-decoration:underline}
  .wrap{max-width:1060px;margin:0 auto;padding:0 22px}
  a:focus-visible,summary:focus-visible,button:focus-visible,input:focus-visible{
    outline:2px solid var(--accent);outline-offset:3px;border-radius:6px}
  .skip{position:absolute;left:-9999px}
  .skip:focus{left:50%;transform:translateX(-50%);top:10px;z-index:9;background:var(--card);
    color:var(--fg);padding:11px 18px;border-radius:10px;border:1px solid var(--line)}

  /* Hero */
  header.hero{position:relative;overflow:hidden;color:#fff;text-align:center;
    background:radial-gradient(120% 140% at 50% -20%,#b3315a 0%,var(--wine) 42%,var(--wine2) 100%);
    padding:76px 22px 88px}
  header.hero.slim{padding:34px 22px 78px}
  .hero .icon{width:132px;height:132px;border-radius:29px;box-shadow:0 22px 60px rgba(0,0,0,.45);
    animation:rise .7s cubic-bezier(.2,.8,.2,1) both}
  .hero.slim .icon{width:66px;height:66px;border-radius:15px;box-shadow:0 10px 26px rgba(0,0,0,.4)}
  .hero h1{font-size:clamp(2.4rem,6vw,3.6rem);margin:.5em 0 .1em;letter-spacing:-.03em;font-weight:800}
  .hero.slim h1{font-size:clamp(1.9rem,4.6vw,2.6rem);margin:.35em 0 .1em}
  /* The hero tagline is a paragraph, not one of the card chips that `.tag` otherwise styles —
     so it keeps the class for continuity but none of the chip's box. */
  .hero p.tag{font-size:1.2rem;opacity:.92;margin:.2em auto 1.6em;max-width:34ch;
    background:none;color:inherit;padding:0;border-radius:0}
  .hero.slim p.tag{font-size:1.05rem;max-width:48ch;margin-bottom:1em}
  .cta{display:inline-flex;align-items:center;gap:10px;background:#fff;color:#111;font-weight:650;
    padding:14px 26px;border-radius:14px;box-shadow:0 10px 30px rgba(0,0,0,.28);transition:transform .15s,box-shadow .15s}
  .cta:hover{transform:translateY(-2px);box-shadow:0 16px 40px rgba(0,0,0,.34);text-decoration:none}
  .cta small{display:block;font-weight:450;opacity:.6;font-size:.72rem}
  .hero .note{margin-top:14px;font-size:.85rem;opacity:.8}
  .hero .note a{color:#fff;text-decoration:underline}
  .wave{position:absolute;left:0;right:0;bottom:-1px;height:60px;background:var(--bg);
    -webkit-mask:radial-gradient(60% 60px at 50% 0,transparent 68%,#000 70%);mask:radial-gradient(60% 60px at 50% 0,transparent 68%,#000 70%)}

  /* Nav — the site is two pages; both say so, from either one. */
  nav.site{display:flex;gap:6px;justify-content:center;flex-wrap:wrap}
  nav.site a{color:#fff;opacity:.82;padding:10px 15px;border-radius:10px;font-size:.95rem;
    min-height:44px;display:inline-flex;align-items:center}
  nav.site a:hover{opacity:1;background:rgba(255,255,255,.14);text-decoration:none}
  nav.site a[aria-current=page]{opacity:1;background:rgba(255,255,255,.20);font-weight:600}

  /* How */
  .how{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;margin:52px 0 10px}
  .how .step{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:20px}
  .how .step b{display:block;font-size:1.05rem;margin-bottom:4px}
  .how .n{width:30px;height:30px;border-radius:50%;background:var(--wine);color:#fff;display:grid;place-items:center;font-weight:700;margin-bottom:10px}
  @media(max-width:720px){.how{grid-template-columns:1fr}}

  /* Games */
  .section-head{display:flex;align-items:baseline;justify-content:space-between;gap:16px;margin:56px 0 18px;flex-wrap:wrap}
  .section-head h2{font-size:1.7rem;letter-spacing:-.02em;margin:0}
  .controls{display:flex;gap:10px;flex-wrap:wrap}
  .controls input{background:var(--card);border:1px solid var(--line);color:var(--fg);
    padding:9px 13px;border-radius:10px;min-width:200px;font-size:.95rem}
  .filters{display:inline-flex;background:var(--card);border:1px solid var(--line);border-radius:10px;overflow:hidden}
  .filters button{border:0;background:transparent;color:var(--muted);padding:9px 14px;font-size:.9rem;cursor:pointer}
  .filters button.on{background:var(--wine);color:#fff}

  .grid{display:grid;gap:20px;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));padding-bottom:10px}
  .card{background:var(--card);border:1px solid var(--line);border-radius:16px;overflow:hidden;
    transition:transform .18s,box-shadow .18s;animation:rise .5s both}
  .card:hover{transform:translateY(-4px);box-shadow:0 16px 34px rgba(0,0,0,.16)}
  .cover{position:relative;aspect-ratio:600/900;background:linear-gradient(160deg,var(--wine),var(--wine2))}
  .cover img{width:100%;height:100%;object-fit:cover;display:block}
  .cover img.noimg,.cover .noimg{display:none}
  .badge{position:absolute;top:10px;left:10px;color:#fff;font-size:.7rem;font-weight:700;
    padding:4px 9px;border-radius:20px;background:rgba(0,0,0,.45);backdrop-filter:blur(6px)}
  .badge.ok{background:var(--ok)} .badge.warn{background:var(--warn)}
  .meta{padding:12px 14px 15px}
  .meta h3{margin:0;font-size:1.02rem;line-height:1.25}
  .sub{color:var(--muted);font-size:.82rem;margin:3px 0 9px}
  .tag{font-size:.72rem;padding:3px 9px;border-radius:6px;background:var(--line);color:var(--muted)}
  .tag.free{background:rgba(47,174,85,.16);color:#2f9c50}
  /* Which storefront a game comes from — the first thing that changes how you install it. */
  .tag.store{font-weight:600}
  .tag.store.steam{background:rgba(44,127,191,.16);color:#2c7fbf}
  .tag.store.battlenet{background:rgba(0,162,232,.16);color:#0080ba}
  /* Purple: the other two stores are both blue, so GOG is the one colour can help tell apart. */
  .tag.store.gog{background:rgba(155,77,202,.16);color:#8438b8}
  .tag.store.standalone{background:rgba(138,138,142,.18);color:var(--muted)}
  @media (prefers-color-scheme:dark){
    .tag.store.steam{color:#7ab8e8}
    .tag.store.battlenet{color:#4cc4ff}
    .tag.store.gog{color:#c98ae8}
  }
  .empty{color:var(--muted);padding:40px;text-align:center;grid-column:1/-1}

  /* FAQ */
  .toc{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:18px 24px;margin:46px 0 4px}
  .toc h2{margin:0 0 8px;font-size:1.05rem}
  .toc ol{margin:0;padding-left:20px;columns:2;column-gap:34px}
  .toc li{margin:4px 0;break-inside:avoid}
  @media(max-width:640px){.toc ol{columns:1}}
  .faq section{margin:46px 0}
  .faq h2{font-size:1.45rem;letter-spacing:-.02em;margin:0 0 3px;scroll-margin-top:18px}
  .faq .lede{color:var(--muted);margin:0 0 16px}
  details.qa{background:var(--card);border:1px solid var(--line);border-radius:14px;margin:10px 0}
  details.qa>summary{cursor:pointer;list-style:none;padding:14px 18px;font-weight:600;
    display:flex;gap:14px;align-items:center;min-height:44px}
  details.qa>summary::-webkit-details-marker{display:none}
  details.qa>summary::after{content:"+";margin-left:auto;color:var(--muted);font-weight:400;
    font-size:1.35rem;line-height:1}
  details.qa[open]>summary::after{content:"\\2013"}
  details.qa[open]>summary{border-bottom:1px solid var(--line)}
  details.qa .a{padding:15px 18px 3px}
  details.qa .a p{margin:0 0 13px}
  details.qa .a ul{margin:0 0 13px;padding-left:20px}
  details.qa .a li{margin:5px 0}
  code{font:.88em/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--line);
    padding:2px 6px;border-radius:5px;overflow-wrap:anywhere}
  .callout{background:var(--card);border:1px solid var(--line);border-left:4px solid var(--wine);
    border-radius:12px;padding:15px 19px;margin:26px 0}
  .callout b{display:block;margin-bottom:3px}
  .download-again{text-align:center;margin:40px 0 0}

  footer{text-align:center;color:var(--muted);font-size:.85rem;padding:46px 22px 60px;border-top:1px solid var(--line);margin-top:50px}
  @keyframes rise{from{opacity:0;transform:translateY(14px)}to{opacity:1;transform:none}}
  @media(prefers-reduced-motion:reduce){*{animation:none!important;transition:none!important}}
"""


def nav(current):
    """The site's pages, linked from every page. `current` marks the one you are on."""
    pages = [("index.html", "Games", "games"),
             ("faq.html", "FAQ", "faq"),
             (REPO, "GitHub", "github")]
    links = []
    for href, label, key in pages:
        mark = ' aria-current="page"' if key == current else ""
        links.append(f'<a href="{href}"{mark}>{label}</a>')
    return '<nav class="site" aria-label="Site">' + "".join(links) + "</nav>"


def site_footer(games):
    playable = sum(1 for g in games if g["status"] == "playable")
    return (f'<footer>{len(games)} games · {playable} playable · '
            f'<a href="index.html">Games</a> · <a href="faq.html">FAQ</a> · '
            f'<a href="{REPO}">Source</a> · Cellar is GPL-3.0 · '
            f'not affiliated with Valve, Blizzard, GOG, Apple, or the game publishers.<br>'
            f'Built on <a href="https://www.winehq.org/">Wine</a>, the Windows compatibility '
            f'layer — Cellar is a launcher over it, and the hard part is theirs.</footer>')


def load_games():
    games = []
    for path in sorted(glob.glob(os.path.join(ROOT, "profiles", "*.toml"))):
        d = parse_toml(path)
        g, comp, art = d.get("game", {}), d.get("compatibility", {}), d.get("art", {})
        appid = g.get("steam_appid", "")
        store = STORES.get(g.get("store", "steam"), STORES["steam"])
        # A profile may bring its own cover; only Steam has one addressable by id.
        portrait = art.get("art_portrait") or (
            f"https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/library_600x900.jpg"
            if appid and g.get("store", "steam") == "steam" else "")
        # `needs_live_steam` is the original spelling of `needs_live_session`; both still read.
        needs_client = comp.get("needs_live_session", comp.get("needs_live_steam", True))
        games.append({
            "name": g.get("name", g.get("slug", "?")),
            "slug": g.get("slug", ""),
            "appid": appid,
            "api": g.get("graphics_api", ""),
            "drm": comp.get("drm", ""),
            "status": comp.get("status", "untested"),
            "store": store,
            "storekey": g.get("store", "steam"),
            "clientfree": not needs_client,
            "installed": comp.get("status") == "playable",
            "portrait": portrait,
        })
    # Playable first, then by name.
    return sorted(games, key=lambda x: (x["status"] != "playable", x["name"].lower()))


def card(g):
    n = html.escape
    label, cls = STATUS.get(g["status"], (g["status"], "muted"))
    store = g["store"]
    tag = ('<span class="tag free">No client needed</span>' if g["clientfree"]
           else f'<span class="tag">Needs {n(store["label"])}</span>')
    art = (f'<img loading="lazy" src="{g["portrait"]}" alt="{n(g["name"])}"'
           f' onerror="this.classList.add(\'noimg\')">') if g["portrait"] else '<div class="noimg"></div>'
    return f'''
      <article class="card" data-name="{n(g['name'].lower())}" data-status="{g['status']}" data-store="{g['storekey']}" data-installed="{str(g['installed']).lower()}">
        <div class="cover">{art}<span class="badge {cls}">{n(label)}</span></div>
        <div class="meta">
          <h3>{n(g['name'])}</h3>
          <p class="sub">{n(g['api'])} · {n(g['drm']) or '—'}</p>
          <div class="tags"><span class="tag store {store['cls']}">{n(store['label'])}</span>{tag}</div>
        </div>
      </article>'''


def render_index(games):
    cards = "\n".join(card(g) for g in games)
    return f'''<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cellar — Windows games on your Mac</title>
<meta name="description" content="Cellar runs Windows games on Apple Silicon Macs: Wine + Apple D3DMetal, per-game profiles, one-click install and play.">
<link rel="icon" href="icon.png">
<style>{CSS}</style></head><body>
<a class="skip" href="#main">Skip to content</a>
<header class="hero">
  <img class="icon" src="icon.png" alt="Cellar">
  <h1>Cellar</h1>
  <p class="tag">Play your Windows games on Apple Silicon. Wine&nbsp;+&nbsp;Apple&nbsp;D3DMetal, one click to install and play.</p>
  <a class="cta" href="{DMG}">▼ Download for macOS <small>Apple Silicon · .dmg</small></a>
  <div class="note">Free &amp; open source · <a href="faq.html">questions &amp; answers</a> · <a href="{REPO}/releases">all releases</a> · <a href="{REPO}">source on GitHub</a></div>
  {nav("games")}
  <div class="wave"></div>
</header>

<main class="wrap" id="main">
  <div class="how">
    <div class="step"><div class="n">1</div><b>Install Cellar</b>Drag it to Applications. It sets up the runtime for you — no Terminal.</div>
    <div class="step"><div class="n">2</div><b>Sign in to your store</b>Steam, Battle.net or GOG — your own account, once per store, not once per game.</div>
    <div class="step"><div class="n">3</div><b>Install &amp; play</b>Pick a game you own, install, and play — Cellar closes everything when you quit.</div>
  </div>

  <div class="section-head">
    <h2>Supported games</h2>
    <div class="controls">
      <input id="q" type="search" placeholder="Search games…" aria-label="Search games" oninput="flt()">
      <div class="filters" id="f">
        <button class="on" data-f="all" onclick="setF(this)">All</button>
        <button data-f="playable" onclick="setF(this)">Playable</button>
        <button data-f="free" onclick="setF(this)">No client needed</button>
      </div>
    </div>
  </div>
  <div class="grid" id="grid">{cards}
    <div class="empty" id="empty" hidden>No games match.</div>
  </div>

  <div class="callout">
    <b>Don't see your game?</b>
    A game is one small profile file — where it came from, its executable and graphics API, and what
    you saw when you ran it. <a href="{REPO}/blob/main/CONTRIBUTING.md">Add one</a>, or read
    <a href="faq.html#games">how this list works</a>.
  </div>
</main>

{site_footer(games)}

<script>
  let mode="all";
  function setF(b){{document.querySelectorAll('#f button').forEach(x=>x.classList.remove('on'));b.classList.add('on');mode=b.dataset.f;flt();}}
  function flt(){{
    const q=(document.getElementById('q').value||'').toLowerCase();
    let shown=0;
    document.querySelectorAll('.card').forEach(c=>{{
      const okQ=c.dataset.name.includes(q);
      const okF=mode==='all'||(mode==='playable'&&c.dataset.status==='playable')||(mode==='free'&&c.querySelector('.tag.free'));
      const vis=okQ&&okF; c.style.display=vis?'':'none'; if(vis)shown++;
    }});
    document.getElementById('empty').hidden=shown>0;
  }}
</script>
</body></html>'''


# The FAQ, as data: (section title, anchor, one-line lede, [(question, answer HTML)]).
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
         "<p><b>Apple Silicon only</b> (M1 and later), on macOS 13 or newer. Cellar's Wine runners "
         "are x86 builds that run under Rosetta 2, with the graphics work handed to Metal on the "
         "Apple GPU — so an Intel Mac is out of scope.</p>"
         "<p>Open the app, or run <code>cellar doctor</code>, and it will tell you what your "
         "machine is missing rather than failing later for an unclear reason.</p>"),
        ("How do I install it?",
         "<p>Download the DMG, drag Cellar to Applications, and open it. On first launch it "
         "introduces itself and offers to sign you in to your stores. You can skip that — Cellar "
         "still opens, and signing in later works identically from <b>Accounts</b> (⌘⇧A) or "
         "<b>Settings → Manage accounts</b>.</p>"
         "<p>Cellar downloads the Wine runner itself the first time a game needs one. No Terminal "
         "required, though there is a full <code>cellar</code> command-line tool if you prefer "
         "one.</p>"),
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
         "<p><b>Once per store.</b> Every Steam bottle shares a single Windows Steam install, so one "
         "sign-in covers your whole Steam library; GOG is one token Cellar holds for the account. "
         "That is exactly why signing in lives on the <b>Accounts</b> screen — ⌘⇧A, or Settings → "
         "Manage accounts — and not on each game's page.</p>"),
        ("Does Cellar see my password?",
         "<p>No. Steam's sign-in happens in Steam's own window inside the bottle, or by scanning a "
         "QR code with the Steam mobile app — the same device flow Steam uses everywhere else. GOG "
         "uses its normal login page and hands back an OAuth token, which Cellar keeps in your "
         "macOS Keychain. Battle.net's sign-in happens entirely inside Blizzard's client.</p>"),
        ("Why does Accounts say Battle.net's sign-in is “not published”?",
         "<p>Because Blizzard writes nothing readable that says who is signed in. Steam does "
         "(<code>loginusers.vdf</code>) and GOG's token names its own account; Battle.net offers no "
         "equivalent.</p>"
         "<p>So rather than show a ✗ that may be wrong, or a ✓ it cannot stand behind, Cellar says "
         "nothing and folds signing in into “open Battle.net” — the one screen where you can "
         "actually do something about it. Where Cellar looks oddly modest about what it knows, this "
         "is usually why.</p>"),
        ("What is the separate “Steam downloads” row?",
         "<p>Two different credentials. The client sign-in is the Windows Steam app inside the "
         "bottle, and it is what a Steamworks game talks to while it runs. The <b>downloads</b> "
         "session is a token used to fetch game files <i>without</i> starting that client — faster, "
         "and enough on its own for games that need no live session. Signing in to one does not "
         "sign you in to the other, so Cellar lists them separately instead of implying they are "
         "the same thing.</p>"),
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
         "<p>Every card on the games page is generated from a profile in the repository, so this "
         "site cannot claim more than the profile does.</p>"),
        ("My game isn't listed. Can I still play it?",
         "<p>Often, yes — the list is what has been <i>profiled</i>, not the limit of what works. A "
         "profile is a small text file naming the game's store, its AppID or install folder, its "
         "executable and graphics API, and which backend to use. Copy the closest existing one and "
         f"adjust it; see <a href=\"{REPO}/blob/main/CONTRIBUTING.md\">CONTRIBUTING.md</a>.</p>"
         "<p>Adding a profile is also how a game reaches this site: the pages regenerate from the "
         "profiles on every push.</p>"),
        ("What about games with anti-cheat?",
         "<p>Competitive games with kernel-level anti-cheat generally do not run, and Cellar will "
         "not make them. It <b>never circumvents DRM or anti-cheat</b> — protection runs through "
         "the translation layer untouched, exactly as the publisher shipped it. Where a profile "
         "knows of an anti-cheat problem it says so plainly, rather than letting you discover it "
         "after a 60&nbsp;GB download.</p>"),
        ("Does the store's client have to be running while I play?",
         "<p>It depends on the game, and the card says which. Steamworks titles usually want a live "
         "Steam session. GOG's games are DRM-free, so nothing needs to run beside them. Cards "
         "marked <b>No client needed</b> install and launch without standing a store client up at "
         "all.</p>"),
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
         "<p>Yes — <b>Settings → Show Metal performance overlay</b> adds an FPS and frametime HUD "
         "to games launched from Cellar.</p>"),
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
         "<p><b>Settings → Open logs</b>, or on disk at "
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
         "from components already there. The same rule is why the store logos in the app are drawn "
         "as vectors in code rather than shipped as image files.</p>"),
        ("Is Cellar affiliated with Valve, Blizzard, GOG or Apple?",
         "<p>No. Cellar is an independent project. Store and product names appear only to say where "
         "a game came from.</p>"),
        ("What licence is it under?",
         f"<p>GPL-3.0. The source, the profile database and this site all live in the "
         f"<a href=\"{REPO}\">repository</a>.</p>"),
    ]),
]


def render_faq(games):
    toc = "\n".join(
        f'        <li><a href="#{anchor}">{title}</a></li>'
        for title, anchor, _lede, _questions in FAQ_SECTIONS)

    sections = []
    for title, anchor, lede, questions in FAQ_SECTIONS:
        # <details> rather than JS: keyboard-operable, findable by the browser's own search, and
        # it still reads correctly with scripting off.
        answers = "\n".join(
            f'''    <details class="qa">
      <summary>{question}</summary>
      <div class="a">{answer}</div>
    </details>''' for question, answer in questions)
        sections.append(f'''  <section id="{anchor}" aria-labelledby="{anchor}-h">
    <h2 id="{anchor}-h">{title}</h2>
    <p class="lede">{lede}</p>
{answers}
  </section>''')
    body = "\n\n".join(sections)

    return f'''<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cellar — questions &amp; answers</title>
<meta name="description" content="How Cellar runs Windows games on an Apple Silicon Mac: what it needs, why it asks you to sign in, what the compatibility ratings mean, and what to do when a game will not start.">
<link rel="icon" href="icon.png">
<style>{CSS}</style></head><body>
<a class="skip" href="#main">Skip to content</a>
<header class="hero slim">
  <img class="icon" src="icon.png" alt="Cellar">
  <h1>Questions &amp; answers</h1>
  <p class="tag">How Cellar works, why it asks what it asks, and what to do when a game won't start.</p>
  {nav("faq")}
  <div class="wave"></div>
</header>

<main class="wrap faq" id="main">
  <nav class="toc" aria-labelledby="toc-h">
    <h2 id="toc-h">On this page</h2>
    <ol>
{toc}
    </ol>
  </nav>

{body}

  <div class="callout">
    <b>Still stuck?</b>
    Open an issue on <a href="{REPO}/issues">GitHub</a> with your Mac, your macOS version, the game,
    and the log from the run that failed — that is usually enough to spot it. Or browse the
    <a href="index.html">{len(games)} profiled games</a>.
  </div>

  <p class="download-again">
    <a class="cta" href="{DMG}">▼ Download Cellar <small>Apple Silicon · .dmg</small></a>
  </p>
</main>

{site_footer(games)}
</body></html>'''


def main():
    games = load_games()
    os.makedirs(OUT, exist_ok=True)
    # Ship the app icon as the site favicon + hero image.
    icon = os.path.join(ROOT, "Resources", "AppIcon.png")
    if os.path.exists(icon):
        shutil.copyfile(icon, os.path.join(OUT, "icon.png"))
    with open(os.path.join(OUT, "index.html"), "w") as f:
        f.write(render_index(games))
    with open(os.path.join(OUT, "faq.html"), "w") as f:
        f.write(render_faq(games))
    open(os.path.join(OUT, ".nojekyll"), "w").close()
    answers = sum(len(questions) for _t, _a, _l, questions in FAQ_SECTIONS)
    print(f"Wrote {OUT}/index.html — {len(games)} games")
    print(f"Wrote {OUT}/faq.html — {len(FAQ_SECTIONS)} sections, {answers} answers")


if __name__ == "__main__":
    main()
