#!/usr/bin/env python3
"""Generate the static Cellar site (hero + games) from profiles/*.toml into site/.

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
    "standalone": {"label": "No store", "cls": "standalone"},
}

STATUS = {  # profile status → (label, css class)
    "playable": ("Playable", "ok"),
    "experimental": ("Experimental", "warn"),
    "untested": ("Untested", "muted"),
}


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


def render(games):
    playable = sum(1 for g in games if g["status"] == "playable")
    cards = "\n".join(card(g) for g in games)
    return f'''<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cellar — Windows games on your Mac</title>
<meta name="description" content="Cellar runs Windows games on Apple Silicon Macs: Wine + Apple D3DMetal, per-game profiles, one-click install and play.">
<link rel="icon" href="icon.png">
<style>
  :root{{color-scheme:light dark;
    --bg:#faf7f6;--fg:#1b1a1c;--card:#ffffff;--muted:#6c666b;--line:#eadfe0;
    --wine:#8e1f3d;--wine2:#5a1228;--accent:#0a84ff;--ok:#2fae55;--warn:#e0872a;}}
  @media (prefers-color-scheme:dark){{:root{{
    --bg:#141013;--fg:#f3eef0;--card:#20191d;--muted:#9c949a;--line:#33272d;}}}}
  *{{box-sizing:border-box}}
  html{{scroll-behavior:smooth}}
  body{{margin:0;background:var(--bg);color:var(--fg);
    font:16px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Roboto,sans-serif;
    -webkit-font-smoothing:antialiased}}
  a{{color:var(--accent);text-decoration:none}}
  .wrap{{max-width:1060px;margin:0 auto;padding:0 22px}}

  /* Hero */
  header.hero{{position:relative;overflow:hidden;color:#fff;text-align:center;
    background:radial-gradient(120% 140% at 50% -20%,#b3315a 0%,var(--wine) 42%,var(--wine2) 100%);
    padding:76px 22px 88px}}
  .hero .icon{{width:132px;height:132px;border-radius:29px;box-shadow:0 22px 60px rgba(0,0,0,.45);
    animation:rise .7s cubic-bezier(.2,.8,.2,1) both}}
  .hero h1{{font-size:clamp(2.4rem,6vw,3.6rem);margin:.5em 0 .1em;letter-spacing:-.03em;font-weight:800}}
  .hero p.tag{{font-size:1.2rem;opacity:.92;margin:.2em auto 1.6em;max-width:34ch}}
  .cta{{display:inline-flex;align-items:center;gap:10px;background:#fff;color:#111;font-weight:650;
    padding:14px 26px;border-radius:14px;box-shadow:0 10px 30px rgba(0,0,0,.28);transition:transform .15s,box-shadow .15s}}
  .cta:hover{{transform:translateY(-2px);box-shadow:0 16px 40px rgba(0,0,0,.34)}}
  .cta small{{display:block;font-weight:450;opacity:.6;font-size:.72rem}}
  .hero .note{{margin-top:14px;font-size:.85rem;opacity:.8}}
  .hero .note a{{color:#fff;text-decoration:underline}}
  .wave{{position:absolute;left:0;right:0;bottom:-1px;height:60px;background:var(--bg);
    -webkit-mask:radial-gradient(60% 60px at 50% 0,transparent 68%,#000 70%);mask:radial-gradient(60% 60px at 50% 0,transparent 68%,#000 70%)}}

  /* How */
  .how{{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;margin:52px 0 10px}}
  .how .step{{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:20px}}
  .how .step b{{display:block;font-size:1.05rem;margin-bottom:4px}}
  .how .n{{width:30px;height:30px;border-radius:50%;background:var(--wine);color:#fff;display:grid;place-items:center;font-weight:700;margin-bottom:10px}}
  @media(max-width:720px){{.how{{grid-template-columns:1fr}}}}

  /* Games */
  .section-head{{display:flex;align-items:baseline;justify-content:space-between;gap:16px;margin:56px 0 18px;flex-wrap:wrap}}
  .section-head h2{{font-size:1.7rem;letter-spacing:-.02em;margin:0}}
  .controls{{display:flex;gap:10px;flex-wrap:wrap}}
  .controls input{{background:var(--card);border:1px solid var(--line);color:var(--fg);
    padding:9px 13px;border-radius:10px;min-width:200px;font-size:.95rem}}
  .filters{{display:inline-flex;background:var(--card);border:1px solid var(--line);border-radius:10px;overflow:hidden}}
  .filters button{{border:0;background:transparent;color:var(--muted);padding:9px 14px;font-size:.9rem;cursor:pointer}}
  .filters button.on{{background:var(--wine);color:#fff}}

  .grid{{display:grid;gap:20px;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));padding-bottom:10px}}
  .card{{background:var(--card);border:1px solid var(--line);border-radius:16px;overflow:hidden;
    transition:transform .18s,box-shadow .18s;animation:rise .5s both}}
  .card:hover{{transform:translateY(-4px);box-shadow:0 16px 34px rgba(0,0,0,.16)}}
  .cover{{position:relative;aspect-ratio:600/900;background:linear-gradient(160deg,var(--wine),var(--wine2))}}
  .cover img{{width:100%;height:100%;object-fit:cover;display:block}}
  .cover img.noimg,.cover .noimg{{display:none}}
  .badge{{position:absolute;top:10px;left:10px;color:#fff;font-size:.7rem;font-weight:700;
    padding:4px 9px;border-radius:20px;background:rgba(0,0,0,.45);backdrop-filter:blur(6px)}}
  .badge.ok{{background:var(--ok)}} .badge.warn{{background:var(--warn)}}
  .meta{{padding:12px 14px 15px}}
  .meta h3{{margin:0;font-size:1.02rem;line-height:1.25}}
  .sub{{color:var(--muted);font-size:.82rem;margin:3px 0 9px}}
  .tag{{font-size:.72rem;padding:3px 9px;border-radius:6px;background:var(--line);color:var(--muted)}}
  .tag.free{{background:rgba(47,174,85,.16);color:#2f9c50}}
  /* Which storefront a game comes from — the first thing that changes how you install it. */
  .tag.store{{font-weight:600}}
  .tag.store.steam{{background:rgba(44,127,191,.16);color:#2c7fbf}}
  .tag.store.battlenet{{background:rgba(0,162,232,.16);color:#0080ba}}
  .tag.store.standalone{{background:rgba(138,138,142,.18);color:var(--muted)}}
  @media (prefers-color-scheme:dark){{
    .tag.store.steam{{color:#7ab8e8}}
    .tag.store.battlenet{{color:#4cc4ff}}
  }}
  .empty{{color:var(--muted);padding:40px;text-align:center;grid-column:1/-1}}

  footer{{text-align:center;color:var(--muted);font-size:.85rem;padding:46px 22px 60px;border-top:1px solid var(--line);margin-top:50px}}
  @keyframes rise{{from{{opacity:0;transform:translateY(14px)}}to{{opacity:1;transform:none}}}}
  @media(prefers-reduced-motion:reduce){{*{{animation:none!important;transition:none!important}}}}
</style></head><body>
<header class="hero">
  <img class="icon" src="icon.png" alt="Cellar">
  <h1>Cellar</h1>
  <p class="tag">Play your Windows games on Apple Silicon. Wine&nbsp;+&nbsp;Apple&nbsp;D3DMetal, one click to install and play.</p>
  <a class="cta" href="{DMG}">▼ Download for macOS <small>Apple Silicon · .dmg</small></a>
  <div class="note">Free &amp; open source · <a href="{REPO}/releases">all releases</a> · <a href="{REPO}">source on GitHub</a></div>
  <div class="wave"></div>
</header>

<main class="wrap">
  <div class="how">
    <div class="step"><div class="n">1</div><b>Install Cellar</b>Drag it to Applications. It sets up the runtime for you — no Terminal.</div>
    <div class="step"><div class="n">2</div><b>Sign in to Steam</b>Use your own account. Cellar keeps Steam out of the way.</div>
    <div class="step"><div class="n">3</div><b>Install &amp; play</b>Pick a game you own, install, and play — Cellar closes everything when you quit.</div>
  </div>

  <div class="section-head">
    <h2>Supported games</h2>
    <div class="controls">
      <input id="q" type="search" placeholder="Search games…" oninput="flt()">
      <div class="filters" id="f">
        <button class="on" data-f="all" onclick="setF(this)">All</button>
        <button data-f="playable" onclick="setF(this)">Playable</button>
        <button data-f="free" onclick="setF(this)">Steam-free</button>
      </div>
    </div>
  </div>
  <div class="grid" id="grid">{cards}
    <div class="empty" id="empty" hidden>No games match.</div>
  </div>
</main>

<footer>{len(games)} games · {playable} playable · Cellar is GPL-3.0 · not affiliated with Valve, Apple, or the game publishers.</footer>

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


def main():
    games = load_games()
    os.makedirs(OUT, exist_ok=True)
    # Ship the app icon as the site favicon + hero image.
    icon = os.path.join(ROOT, "Resources", "AppIcon.png")
    if os.path.exists(icon):
        shutil.copyfile(icon, os.path.join(OUT, "icon.png"))
    with open(os.path.join(OUT, "index.html"), "w") as f:
        f.write(render(games))
    open(os.path.join(OUT, ".nojekyll"), "w").close()
    print(f"Wrote {OUT}/index.html — {len(games)} games")


if __name__ == "__main__":
    main()
