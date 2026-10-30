#!/usr/bin/env python3
"""Check that a pull request arrives verified: the bar every author is held to, AI or not.

    python3 Scripts/check-pr.py --body body.md --files changed.txt [--author LOGIN]

CI runs it on every PR (.github/workflows/pr-checklist.yml) with the PR's description and the files
it changes. It fails (exit 1), naming each problem, when the PR:

  - links no issue with "Closes #N" (or Fixes/Resolves) — every task is an issue first;
  - has no "How it was verified" section, or ticks nothing in it;
  - changes Swift under Sources/ but no test under Tests/, unless it says why on a line of its own:
        No tests needed: <the reason>
    A reason is a sentence about this change ("only reflows a comment"), not a shrug.

Bots that open PRs from a template of their own (Dependabot) are exempt; their changes are covered
by the build and tests like anyone else's.

Standard library only, Python 3.9 floor (skills/python.md).
"""
import argparse
import re
import sys

BOTS = {"dependabot[bot]", "github-actions[bot]"}

ISSUE_LINK = re.compile(r"\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\s+(?:[\w.-]+/[\w.-]+)?#\d+", re.IGNORECASE)
VERIFIED_HEADING = re.compile(r"^#{2,3}\s*How it was verified\s*$", re.IGNORECASE | re.MULTILINE)
NEXT_HEADING = re.compile(r"^#{1,3}\s", re.MULTILINE)
TICKED = re.compile(r"^\s*[-*]\s*\[[xX]\]\s*\S", re.MULTILINE)
NO_TESTS = re.compile(r"^\s*No tests needed:\s*(.+?)\s*$", re.IGNORECASE | re.MULTILINE)
COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)

# Words that are not a reason. The point of the line is to make the author think about it once.
NON_REASONS = {"n/a", "na", "none", "no", "-", "trivial", "small change", "tbd", "todo"}


def section(body, heading):
    """The text under `heading` up to the next heading, or None when there is no such section."""
    match = heading.search(body)
    if not match:
        return None
    rest = body[match.end():]
    following = NEXT_HEADING.search(rest)
    return rest[:following.start()] if following else rest


def touches_code(files):
    return any(f.startswith("Sources/") and f.endswith(".swift") for f in files)


def touches_tests(files):
    return any(f.startswith("Tests/") for f in files)


def problems(body, files, author=""):
    """Every reason this PR is not ready, as sentences a contributor can act on."""
    if author in BOTS:
        return []
    # Template guidance lives in HTML comments; an untouched template must not pass on its hints.
    body = COMMENT.sub("", body or "")
    found = []

    if not ISSUE_LINK.search(body):
        found.append('Link the issue this PR delivers with "Closes #N". Every task is an issue first '
                     "(docs/RELEASING.md); open one if it does not exist.")

    verified = section(body, VERIFIED_HEADING)
    if verified is None:
        found.append('Add a "## How it was verified" section (the PR template has it) saying which rungs '
                     "of the verification ladder in AGENTS.md this change reached.")
    elif not TICKED.search(verified):
        found.append('Tick what you actually ran under "How it was verified". If you could not run a rung, '
                     "leave it unticked and say who has to, but at least one check must have been run.")

    if touches_code(files) and not touches_tests(files):
        reason = NO_TESTS.search(body)
        given = reason.group(1).strip().rstrip(".").lower() if reason else ""
        if not reason or given in NON_REASONS or len(given) < 12:
            found.append("This changes Swift under Sources/ but no test under Tests/. Add or update a test "
                         "that fails without the change, or explain on its own line: "
                         '"No tests needed: <why this change cannot be tested or is already covered>".')
    return found


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--body", required=True, help="file holding the PR description")
    parser.add_argument("--files", required=True, help="file listing the changed paths, one per line")
    parser.add_argument("--author", default="", help="the PR author's login")
    args = parser.parse_args(argv)

    with open(args.body, encoding="utf-8") as handle:
        body = handle.read()
    with open(args.files, encoding="utf-8") as handle:
        files = [line.strip() for line in handle if line.strip()]

    found = problems(body, files, args.author)
    if not found:
        print(f"PR checklist: OK ({len(files)} changed file(s)).")
        return 0
    print("PR checklist: this pull request is not ready to merge.\n")
    for item in found:
        print(f"  - {item}")
    print("\nEdit the PR description to fix it; this check runs again on every edit.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
