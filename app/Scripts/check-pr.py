#!/usr/bin/env python3
"""Check that a pull request arrives verified: the bar every author is held to, AI or not.

    python3 app/Scripts/check-pr.py --body body.md --files changed.txt [--author LOGIN]

CI runs it on every PR (.github/workflows/pr-checklist.yml) with the PR's description and the files
it changes. It fails (exit 1), naming each problem, when the PR:

  - links no issue with "Closes #N" (or Fixes/Resolves) — every task is an issue first;
  - has no "How it was verified" section, or ticks nothing in it;
  - changes Swift under app/src/ but no test under app/tests/, unless it says why on a line of its own:
        No tests needed: <the reason>
    A reason is a sentence about this change ("only reflows a comment"), not a shrug;
  - changes app code, a profile or the Dock shim without a "Delivery checklist" section, or leaves a
    box in it unticked without saying why after "n/a:" (docs/DELIVERY-CHECKLIST.md);
  - asks players to run a command in its "Notes for the release": Cellar repairs itself (check P1).

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
DELIVERY_HEADING = re.compile(r"^#{2,3}\s*Delivery checklist\s*$", re.IGNORECASE | re.MULTILINE)
RELEASE_HEADING = re.compile(r"^#{2,3}\s*Notes for the release\s*$", re.IGNORECASE | re.MULTILINE)
BOX = re.compile(r"^\s*[-*]\s*\[(?P<mark>[ xX])\]\s*(?P<text>.*)$", re.MULTILINE)
NOT_APPLICABLE = re.compile(r"\bn/a:\s*(?P<reason>.*)$", re.IGNORECASE)
# A command handed to the player: a fenced block, a "$ " prompt, or inline code that starts with a shell verb.
SHELL_VERBS = r"(?:sh|bash|zsh|cd|sudo|cellar|curl|cp|mv|rm|defaults|xattr|chmod|open|python3?|swift|git)"
PLAYER_COMMAND = re.compile(r"```|^\s*\$\s+\S|`" + SHELL_VERBS + r"\s[^`]*`", re.MULTILINE)

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
    """Swift in the executables (app/src/) or in a library package's Sources/ (app/Packages/*/Sources/)."""
    def is_code(f):
        parts = f.split("/")
        return f.endswith(".swift") and (f.startswith("app/src/") or (
            len(parts) > 3 and parts[:2] == ["app", "Packages"] and parts[3] == "Sources"))
    return any(is_code(f) for f in files)


def touches_tests(files):
    """The app's test targets (app/tests/), or a library package's own Tests/."""
    return any(f.startswith("app/tests/") or (f.startswith("app/Packages/") and "/Tests/" in f)
               for f in files)


def touches_delivery(files):
    """Anything that can change what a player gets: app code, a game profile, the Dock shim."""
    return touches_code(files) or any(f.startswith(("profiles/", "app/Shim/")) for f in files)


def delivery_problems(checklist):
    """The unticked delivery boxes that do not say why they cannot apply, as one sentence."""
    boxes = list(BOX.finditer(checklist))
    if not boxes:
        return ['The "Delivery checklist" section has no boxes. Copy them from the PR template.']
    open_lines = []
    for box in boxes:
        if box.group("mark") != " ":
            continue
        text = box.group("text").strip()
        reason = NOT_APPLICABLE.search(text)
        if not reason or len(reason.group("reason").strip()) < 8:
            open_lines.append(text.split(":")[0].strip() or text)
    if not open_lines:
        return []
    return ["Delivery checklist: " + ", ".join(open_lines) + (" is" if len(open_lines) == 1 else " are")
            + ' unticked. Tick each once its evidence is in this PR, or say on the same line why it '
            'cannot apply after "n/a:" (docs/DELIVERY-CHECKLIST.md).']
    return found


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
            found.append("This changes Swift under app/src/ but no test under app/tests/. Add or update a test "
                         "that fails without the change, or explain on its own line: "
                         '"No tests needed: <why this change cannot be tested or is already covered>".')

    if touches_delivery(files):
        checklist = section(body, DELIVERY_HEADING)
        if checklist is None:
            found.append('Add the "## Delivery checklist" section from the PR template: this changes what a '
                         "player gets, so every line in docs/DELIVERY-CHECKLIST.md is answered before it merges.")
        else:
            found.extend(delivery_problems(checklist))

    notes = section(body, RELEASE_HEADING)
    if notes and PLAYER_COMMAND.search(notes):
        found.append('"Notes for the release" asks players to run a command. Players never need Terminal '
                     "(check P1): make Cellar do it, and describe what the player sees instead.")
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
