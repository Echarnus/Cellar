#!/usr/bin/env python3
"""Generate the static "supported games" site from profiles/*.toml into site/.

Data-driven: every game card comes from a profile, so the page can't drift from what Cellar
actually supports. Run: python3 Scripts/gen-site.py
"""
import glob
import html
import os
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
        """Minimal TOML: [sections] and key = value, enough for Cellar's flat profiles."""
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

STATUS_BADGE = {
    "playable": ("Playable", "#34c759"),
    "experimental": ("Experimental", "#ff9f0a"),
    "untested": ("Untested", "#8e8e93"),
}


def load_games():
    games = []
    for path in sorted(glob.glob(os.path.join(ROOT, "profiles", "*.toml"))):
        data = parse_toml(path)
        g = data.get("game", {})
        comp = data.get("compatibility", {})
        runner = data.get("runner", {})
        install = data.get("install", {})
        needs_steam = comp.get("needs_live_steam", True)
        games.append({
            "name": g.get("name", g.get("slug", "?")),
            "slug": g.get("slug", ""),
            "appid": g.get("steam_appid", ""),
            "engine": g.get("engine", ""),
            "api": g.get("graphics_api", ""),
            "drm": comp.get("drm", ""),
            "status": comp.get("status", "untested"),
            "runner": runner.get("id", "wineforge"),
            "steamfree": (not needs_steam),
            "download": "DepotDownloader" if install.get("method") == "depot" else "Windows Steam",
            "notes": comp.get("notes", g.get("notes", "")),
        })
    return games


def card(g):
    label, colour = STATUS_BADGE.get(g["status"], (g["status"], "#8e8e93"))
    steam = ('<span class="tag ok">Steam-free</span>' if g["steamfree"]
             else '<span class="tag">Needs Steam</span>')
    n = html.escape
    return f"""
      <article class="card">
        <div class="row"><h2>{n(g['name'])}</h2>
          <span class="badge" style="background:{colour}">{n(label)}</span></div>
        <dl>
          <div><dt>Graphics</dt><dd>{n(g['api'])} → D3DMetal</dd></div>
          <div><dt>Engine</dt><dd>{n(g['engine'])}</dd></div>
          <div><dt>DRM</dt><dd>{n(g['drm'])}</dd></div>
          <div><dt>Runner</dt><dd>{n(g['runner'])}</dd></div>
          <div><dt>Download</dt><dd>{n(g['download'])}</dd></div>
          <div><dt>Play</dt><dd>{steam}</dd></div>
        </dl>
        <p class="notes">{n(g['notes'])}</p>
        <code>cellar launch {n(g['slug'])}</code>
      </article>"""


def render(games):
    playable = sum(1 for g in games if g["status"] == "playable")
    cards = "\n".join(card(g) for g in games)
    return f"""<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cellar — Supported Games</title>
<style>
  :root {{ color-scheme: light dark; --bg:#faf7f5; --fg:#1c1c1e; --card:#fff; --muted:#6b6b70; --line:#e6e0dc; --wine:#7b1e3b; }}
  @media (prefers-color-scheme: dark) {{ :root {{ --bg:#161113; --fg:#f2eee9; --card:#211a1d; --muted:#9a9298; --line:#332a2e; }} }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; background:var(--bg); color:var(--fg); }}
  header {{ background:linear-gradient(160deg,var(--wine),#3a0e1c); color:#fff; padding:56px 24px 40px; text-align:center; }}
  header h1 {{ margin:0 0 6px; font-size:2.4rem; letter-spacing:-.02em; }}
  header p {{ margin:4px 0; opacity:.9; }}
  header a {{ color:#fff; }}
  main {{ max-width:1000px; margin:0 auto; padding:28px 20px 60px; }}
  .grid {{ display:grid; gap:18px; grid-template-columns:repeat(auto-fill,minmax(300px,1fr)); }}
  .card {{ background:var(--card); border:1px solid var(--line); border-radius:14px; padding:18px 20px; }}
  .row {{ display:flex; align-items:center; justify-content:space-between; gap:10px; }}
  .card h2 {{ font-size:1.15rem; margin:0; }}
  .badge {{ color:#fff; font-size:.72rem; font-weight:600; padding:3px 9px; border-radius:20px; white-space:nowrap; }}
  dl {{ margin:14px 0 10px; display:grid; gap:6px; }}
  dl div {{ display:flex; justify-content:space-between; gap:12px; font-size:.9rem; border-bottom:1px dashed var(--line); padding-bottom:5px; }}
  dt {{ color:var(--muted); }} dd {{ margin:0; text-align:right; }}
  .tag {{ font-size:.75rem; padding:2px 8px; border-radius:6px; background:var(--line); color:var(--muted); }}
  .tag.ok {{ background:#34c75922; color:#2a9c48; }}
  .notes {{ font-size:.85rem; color:var(--muted); min-height:1.2em; }}
  code {{ display:block; margin-top:10px; background:#0000000d; padding:8px 10px; border-radius:8px; font-size:.82rem; overflow:auto; }}
  @media (prefers-color-scheme: dark) {{ code {{ background:#ffffff10; }} }}
  footer {{ text-align:center; color:var(--muted); font-size:.85rem; padding:30px 20px 50px; }}
</style></head><body>
<header>
  <h1>🍷 Cellar</h1>
  <p>Run Windows games on Apple Silicon Macs — Wine + Apple D3DMetal, per-game profiles.</p>
  <p>{len(games)} profiles · {playable} playable · <a href="https://github.com/Echarnus/Cellar">GitHub</a></p>
</header>
<main>
  <p style="color:var(--muted);text-align:center;margin:0 0 22px">
    Auto-generated from Cellar's profile database. "Steam-free" means the game runs with no Steam
    client at all (DRM-free titles); the rest run with Steam kept silent in the background.</p>
  <div class="grid">{cards}
  </div>
</main>
<footer>Generated from <code style="display:inline;padding:2px 6px">profiles/*.toml</code> · Cellar is GPL-3.0 · not affiliated with Valve, Apple, or the game publishers.</footer>
</body></html>"""


def main():
    games = load_games()
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "index.html"), "w") as f:
        f.write(render(games))
    open(os.path.join(OUT, ".nojekyll"), "w").close()
    print(f"Wrote {OUT}/index.html — {len(games)} games")


if __name__ == "__main__":
    main()
