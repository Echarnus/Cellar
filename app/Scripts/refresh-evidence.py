#!/usr/bin/env python3
"""Copy what public sources say about each Steam game into its profile (#286).

    python3 app/Scripts/refresh-evidence.py            # read the sources, rewrite the profiles
    python3 app/Scripts/refresh-evidence.py --check    # read them, print what would change, exit 1 if anything would

For every profile with a `steam_appid` it reads:

- ProtonDB's summary tier (how the game runs for Linux players under Proton, Valve's Wine):
  `protondb = "platinum" | "gold" | "silver" | "bronze" | "borked" | "pending"`
- Valve's Steam Deck rating: `steam_deck = "verified" | "playable" | "unsupported" | "unknown"`
- AreWeAntiCheatYet's word on the game's anti-cheat under Proton, when it lists the game:
  `anticheat_on_linux = "supported" | "running" | "planned" | "broken" | "denied"`

and stamps `evidence_checked = "YYYY-MM-DD"`. These are evidence for Cellar's estimate
(`CompatibilityForecast`, docs/COMPATIBILITY.md), never a status: `status` stays what a test on a
Mac found. A source that can't be reached leaves its value as it was, so a network failure never
wipes evidence. Standard library only, Python 3.9 floor.
"""
import argparse
import datetime
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROFILES = os.path.join(ROOT, "profiles")
AGENT = "Cellar-evidence/1.0 (+https://github.com/Echarnus/Cellar)"

PROTONDB = "https://www.protondb.com/api/v1/reports/summaries/{appid}.json"
DECK = "https://store.steampowered.com/saleaction/ajaxgetdeckappcompatibilityreport?nAppID={appid}&l=english"
AWACY = "https://raw.githubusercontent.com/AreWeAntiCheatYet/AreWeAntiCheatYet/master/games.json"

PROTONDB_TIERS = {"platinum", "gold", "silver", "bronze", "borked", "pending"}
DECK_CATEGORIES = {0: "unknown", 1: "unsupported", 2: "playable", 3: "verified"}
AWACY_STATUSES = {"supported", "running", "planned", "broken", "denied"}
KEYS = ("protondb", "steam_deck", "anticheat_on_linux", "evidence_checked")


def fetch_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def protondb_tier(summary):
    tier = str((summary or {}).get("tier", "")).lower()
    return tier if tier in PROTONDB_TIERS else None


def deck_rating(report):
    results = (report or {}).get("results") or {}
    return DECK_CATEGORIES.get(results.get("resolved_category"))


def awacy_index(games):
    """Steam AppID → AreWeAntiCheatYet status, lower-cased."""
    index = {}
    for game in games or []:
        appid = str((game.get("storeIds") or {}).get("steam", "")).strip()
        status = str(game.get("status", "")).lower()
        if appid and status in AWACY_STATUSES:
            index[appid] = status
    return index


def read_fields(text):
    """The flat scan the app uses (ProfileStore.fields): last value wins, sections ignored."""
    fields = {}
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("#") or line.startswith("[") or "=" not in line:
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        if " #" in value:
            value = value[: value.index(" #")]
        fields[key] = value.strip().strip('"')
    return fields


def set_fields(text, values):
    """Write each key into the [compatibility] section: replace its line, or add it after `status`."""
    lines = text.split("\n")
    for key in KEYS:
        if key not in values:
            continue
        new = f'{key:<27} = "{values[key]}"'
        pattern = re.compile(rf"^\s*{re.escape(key)}\s*=")
        found = [i for i, line in enumerate(lines) if pattern.match(line)]
        if found:
            lines[found[-1]] = new
            continue
        anchor = None
        in_compat = False
        for i, line in enumerate(lines):
            stripped = line.strip()
            if stripped.startswith("["):
                in_compat = stripped == "[compatibility]"
            elif in_compat and re.match(r"^(status|notes|protondb|steam_deck|anticheat_on_linux|evidence_checked)\s*=", stripped):
                anchor = i
        if anchor is None:
            raise ValueError("no [compatibility] status line to put the evidence beside")
        lines.insert(anchor + 1, new)
    return "\n".join(lines)


def gather(appid, awacy, fetch=fetch_json):
    """The values the sources give for one AppID. A source that fails is left out, not blanked."""
    values = {}
    try:
        tier = protondb_tier(fetch(PROTONDB.format(appid=appid)))
        if tier:
            values["protondb"] = tier
    except Exception as error:  # noqa: BLE001 - a 404 means ProtonDB has no reports yet
        if getattr(error, "code", None) == 404:
            values["protondb"] = "pending"
        else:
            print(f"  ProtonDB unreachable for {appid}: {error}", file=sys.stderr)
    try:
        rating = deck_rating(fetch(DECK.format(appid=appid)))
        if rating:
            values["steam_deck"] = rating
    except Exception as error:  # noqa: BLE001
        print(f"  Steam Deck rating unreachable for {appid}: {error}", file=sys.stderr)
    if awacy is not None and str(appid) in awacy:
        values["anticheat_on_linux"] = awacy[str(appid)]
    return values


def refresh(profiles_dir, fetch=fetch_json, today=None, write=True):
    """Refresh every Steam profile. Returns {slug: {key: (old, new)}} for what changed."""
    today = today or datetime.date.today().isoformat()
    try:
        awacy = awacy_index(fetch(AWACY))
    except Exception as error:  # noqa: BLE001
        print(f"AreWeAntiCheatYet unreachable: {error}", file=sys.stderr)
        awacy = None
    changes = {}
    for name in sorted(os.listdir(profiles_dir)):
        if not name.endswith(".toml"):
            continue
        path = os.path.join(profiles_dir, name)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        fields = read_fields(text)
        appid = fields.get("steam_appid", "").strip()
        if not appid.isdigit() or fields.get("generated") == "true":
            continue
        values = gather(appid, awacy, fetch)
        if not values:
            continue
        changed = {k: (fields.get(k), v) for k, v in values.items() if fields.get(k) != v}
        if not changed:
            continue
        values["evidence_checked"] = today
        changes[name[:-5]] = changed
        if write:
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(set_fields(text, values))
    return changes


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true", help="print what would change and exit 1 if anything would")
    parser.add_argument("--profiles", default=PROFILES)
    args = parser.parse_args(argv)
    changes = refresh(args.profiles, write=not args.check)
    for slug, changed in changes.items():
        print(slug)
        for key, (old, new) in changed.items():
            print(f"  {key}: {old or '-'} -> {new}")
    if not changes:
        print("Every profile's public evidence is current.")
    return 1 if (args.check and changes) else 0


if __name__ == "__main__":
    sys.exit(main())
