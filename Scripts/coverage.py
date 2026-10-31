#!/usr/bin/env python3
"""Hold Cellar's line coverage to a ratchet: it may go up, never down.

Run by `sh Scripts/test.sh --coverage`, which hands it the report SwiftPM wrote:

    python3 Scripts/coverage.py .build/arm64-apple-macosx/debug/codecov/Cellar.json
    python3 Scripts/coverage.py --update REPORT      # raise the baseline to what REPORT measured

Measures the libraries the tests can import, CellarDomain, CellarKit and CellarUI, and compares each with
Tests/coverage-baseline.json. Fails (exit 1) when a target falls more than TOLERANCE points below
its baseline. `--update` only ever raises a number, so it cannot be used to paper over a drop.

The executables (the CLI and the app) are not measured: a test cannot import an executable, which
is exactly why logic lives in CellarKit and views worth checking live in CellarUI (AGENTS.md).

Writes a Markdown summary to $GITHUB_STEP_SUMMARY when CI sets it, so the numbers sit on the run's
page. Standard library only, Python 3.9 floor (skills/python.md).
"""
import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = os.path.join(ROOT, "Tests", "coverage-baseline.json")
TARGETS = ("CellarDomain", "CellarKit", "CellarUI")

# Two macOS images and a suite that watches real processes do not land on the identical line count
# every run, so a hair of slack — far less than any untested function would cost.
TOLERANCE = 0.3
# How many of the least-covered files to name, as the place to start.
WORST = 8


def target_of(filename):
    """The library a source file belongs to, or None for tests, dependencies and executables."""
    parts = filename.replace("\\", "/").split("/")
    for i, part in enumerate(parts[:-1]):
        if part == "Sources" and parts[i + 1] in TARGETS:
            # A dependency checked out under .build has a Sources/ of its own.
            if ".build" in parts[:i]:
                return None
            return parts[i + 1]
    return None


def measure(report):
    """{target: {"covered": n, "count": n, "files": [(percent, path, covered, count)]}}."""
    with open(report, encoding="utf-8") as handle:
        data = json.load(handle)
    totals = {t: {"covered": 0, "count": 0, "files": []} for t in TARGETS}
    for export in data.get("data", []):
        for entry in export.get("files", []):
            target = target_of(entry.get("filename", ""))
            if target is None:
                continue
            lines = entry.get("summary", {}).get("lines", {})
            count, covered = int(lines.get("count", 0)), int(lines.get("covered", 0))
            totals[target]["count"] += count
            totals[target]["covered"] += covered
            if count:
                rel = os.path.relpath(entry["filename"], ROOT) if os.path.isabs(entry["filename"]) else entry["filename"]
                totals[target]["files"].append((100.0 * covered / count, rel, covered, count))
    return totals


def percent(total):
    return 100.0 * total["covered"] / total["count"] if total["count"] else 0.0


def load_baseline():
    try:
        with open(BASELINE, encoding="utf-8") as handle:
            return {k: float(v) for k, v in json.load(handle).items() if k in TARGETS}
    except FileNotFoundError:
        return {}


def save_baseline(baseline):
    with open(BASELINE, "w", encoding="utf-8") as handle:
        json.dump({t: baseline.get(t, 0.0) for t in TARGETS}, handle, indent=2)
        handle.write("\n")


def judge(measured, baseline, tolerance=TOLERANCE):
    """The failures, as sentences: a target below its baseline, or one the report never saw."""
    failures = []
    for target in TARGETS:
        floor = baseline.get(target, 0.0)
        now = measured.get(target)
        if now is None:
            failures.append(f"{target}: no lines were measured — was it built with coverage?")
        elif now + tolerance < floor:
            failures.append(f"{target}: line coverage fell to {now:.1f}% from a baseline of {floor:.1f}%. "
                            f"Add tests for the code this change brings in.")
    return failures


def summary(totals, measured, baseline, failures):
    rows = ["## Test coverage", "", "| Target | Lines | Coverage | Baseline |", "|---|---|---|---|"]
    for target in TARGETS:
        t = totals[target]
        rows.append(f"| {target} | {t['covered']} / {t['count']} | {measured.get(target, 0.0):.1f}% "
                    f"| {baseline.get(target, 0.0):.1f}% |")
    rows += ["", "**Least covered in CellarKit** — the place to start:", ""]
    for pct, path, covered, count in sorted(totals["CellarKit"]["files"])[:WORST]:
        rows.append(f"- `{path}` — {pct:.0f}% ({covered} of {count} lines)")
    rows.append("")
    rows += [f"- ❌ {f}" for f in failures] or ["Coverage is at or above the baseline."]
    return "\n".join(rows) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("report", help="the JSON SwiftPM writes with --enable-code-coverage")
    parser.add_argument("--update", action="store_true", help="raise the baseline to this report")
    args = parser.parse_args(argv)

    totals = measure(args.report)
    measured = {t: round(percent(v), 1) for t, v in totals.items() if v["count"]}
    baseline = load_baseline()

    if args.update:
        # Rounded down, so the next run of the same code cannot fail by a rounding step.
        raised = {t: max(baseline.get(t, 0.0), int(measured.get(t, 0.0) * 10) / 10.0) for t in TARGETS}
        save_baseline(raised)
        for t in TARGETS:
            print(f"{t}: baseline {baseline.get(t, 0.0):.1f}% → {raised[t]:.1f}%")
        return 0

    failures = judge(measured, baseline)
    text = summary(totals, measured, baseline, failures)
    print(text)
    step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary:
        with open(step_summary, "a", encoding="utf-8") as handle:
            handle.write(text)
    for target in TARGETS:
        if measured.get(target, 0.0) >= baseline.get(target, 0.0) + 1.0:
            print(f"note: {target} is a point or more above its baseline. Lock that in: "
                  f"python3 Scripts/coverage.py --update {args.report}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
