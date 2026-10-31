#!/usr/bin/env python3
"""Write the notes for a Cellar release: the issues it closes, grouped by label.

    python3 Scripts/release-notes.py --repo Echarnus/Cellar --tag v0.4.0 --out dist/RELEASE_NOTES.md

An issue belongs to a release when either
  * a pull request merged between the previous tag and this one closes it ("Closes #12"), or
  * it was closed as completed in that window (a fix pushed straight to main with "Fixes #12").

Issues labelled `skip-changelog`, and issues closed as not planned or as duplicates, are left out.
GitHub's own list of merged pull requests follows, then how to install.

Runs in the release workflow with GH_TOKEN set; needs `git` with full history and the `gh` CLI.
Stdlib only, Python 3.9 floor (skills/python.md).
"""
import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone

# Section order and wording. An issue lands in the first section whose label it carries.
SECTIONS = [
    ("breaking-change", "Breaking changes"),
    ("security", "Security"),
    ("bug", "Fixes"),
    ("enhancement", "New and improved"),
    ("performance", "Performance"),
    ("ux", "Look and feel"),
    ("compatibility", "Compatibility"),
    ("networking", "Online play"),
    ("game-profile", "Games"),
    ("legal", "Licences and credits"),
    ("documentation", "Documentation"),
    ("ci", "Delivery"),
    ("dependencies", "Dependencies"),
]
OTHER = "Other changes"
SKIP = "skip-changelog"


# The install section, the same in every release. User-facing copy (skills/ux.md).
INSTALL = (
    "Download **Cellar.dmg**, open it and drag Cellar into Applications. Cellar is not "
    "notarised yet, so macOS blocks the first launch: open **System Settings → Privacy & "
    "Security**, scroll to Cellar and click **Open Anyway** (right-click → Open no longer "
    "bypasses this since macOS 15). Cellar then sets up its runtime, you sign in to your "
    "store, and you pick a game to play."
)
REQUIREMENTS = (
    "Requires an Apple Silicon Mac on macOS 27 or later (every M1 Mac can run it). Today's runners are Intel builds that "
    "run under Rosetta 2, which macOS 28 keeps only for games: `cellar doctor` says where your "
    "Mac stands."
)
DOWNLOADS = (
    "`Cellar-App-*.zip` is the same app without the installer, and `Cellar-CLI-*.zip` is the "
    "`cellar` command. `SHA256SUMS.txt` lists every download's checksum, and each one carries "
    "a [build provenance attestation](https://github.com/%s/attestations)."
)


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout.strip()


def gh_json(*args):
    return json.loads(run("gh", *args) or "null")


def previous_tag(tag):
    try:
        return run("git", "describe", "--tags", "--abbrev=0", "--match", "v*", tag + "^")
    except subprocess.CalledProcessError:
        return None  # the first release


def tag_time(tag):
    return run("git", "log", "-1", "--format=%cI", tag)


def released_at(repo, tag):
    """When the previous release went out, so the window starts where its notes stopped."""
    try:
        return gh_json("api", "repos/%s/releases/tags/%s" % (repo, tag))["published_at"]
    except subprocess.CalledProcessError:
        return tag_time(tag)


def merged_prs(repo, prev, tag):
    span = "%s..%s" % (prev, tag) if prev else tag
    shas = run("git", "rev-list", "--first-parent", span).split()
    numbers = set()
    for sha in shas:
        for pr in gh_json("api", "repos/%s/commits/%s/pulls" % (repo, sha)) or []:
            if pr.get("merged_at"):
                numbers.add(pr["number"])
    return numbers


CLOSING = """
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      closingIssuesReferences(first: 50) {
        nodes { number title url state stateReason labels(first: 20) { nodes { name } } }
      }
    }
  }
}
"""


def issues_closed_by(repo, number):
    owner, name = repo.split("/")
    data = gh_json("api", "graphql", "-f", "query=" + CLOSING, "-F", "owner=" + owner,
                   "-F", "name=" + name, "-F", "number=%d" % number)
    nodes = data["data"]["repository"]["pullRequest"]["closingIssuesReferences"]["nodes"]
    return [
        {
            "number": n["number"],
            "title": n["title"],
            "url": n["url"],
            "labels": [label["name"] for label in n["labels"]["nodes"]],
            "completed": n["state"] == "CLOSED" and n["stateReason"] in (None, "COMPLETED"),
        }
        for n in nodes
    ]


def issues_closed_between(repo, since, until):
    query = "repo:%s is:issue is:closed reason:completed closed:%s..%s" % (repo, since, until)
    found, page = [], 1
    while True:
        data = gh_json("api", "-X", "GET", "search/issues", "-f", "q=" + query,
                       "-F", "per_page=100", "-F", "page=%d" % page)
        for item in data["items"]:
            found.append({
                "number": item["number"],
                "title": item["title"],
                "url": item["html_url"],
                "labels": [label["name"] for label in item["labels"]],
                "completed": True,
            })
        if len(data["items"]) < 100:
            return found
        page += 1


def pull_request_list(repo, tag, prev):
    args = ["api", "repos/%s/releases/generate-notes" % repo, "-f", "tag_name=" + tag]
    if prev:
        args += ["-f", "previous_tag_name=" + prev]
    try:
        return gh_json(*args)["body"]
    except subprocess.CalledProcessError as err:
        print("warning: no pull request list: %s" % err.stderr.strip(), file=sys.stderr)
        return ""


def section_of(issue):
    for label, title in SECTIONS:
        if label in issue["labels"]:
            return title
    return OTHER


def render(version, issues, prs, repo):
    lines = ["Cellar %s runs Windows games on Apple Silicon Macs." % version, ""]
    if issues:
        grouped = {}
        for issue in sorted(issues, key=lambda i: i["number"]):
            grouped.setdefault(section_of(issue), []).append(issue)
        for title in [t for _, t in SECTIONS] + [OTHER]:
            if title not in grouped:
                continue
            lines += ["## %s" % title, ""]
            lines += ["- %s ([#%d](%s))" % (i["title"], i["number"], i["url"]) for i in grouped[title]]
            lines.append("")
    else:
        lines += ["No tracked issues were closed in this release.", ""]
    if prs:
        lines += [prs.replace("## What's Changed", "## Pull requests"), ""]
    lines += ["## Install", "", INSTALL, "", REQUIREMENTS, "", DOWNLOADS % repo, "",
              "Supported games: https://echarnus.github.io/Cellar/", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", required=True, help="owner/name")
    parser.add_argument("--tag", required=True, help="the tag being released, e.g. v0.4.0")
    parser.add_argument("--out", required=True, help="where to write the Markdown")
    args = parser.parse_args()

    prev = previous_tag(args.tag)
    since = released_at(args.repo, prev) if prev else "2000-01-01T00:00:00Z"
    until = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    issues = {}
    for number in sorted(merged_prs(args.repo, prev, args.tag)):
        for issue in issues_closed_by(args.repo, number):
            if issue["completed"]:
                issues[issue["number"]] = issue
    for issue in issues_closed_between(args.repo, since, until):
        issues.setdefault(issue["number"], issue)
    kept = [i for i in issues.values() if SKIP not in i["labels"]]

    notes = render(args.tag.lstrip("v"), kept, pull_request_list(args.repo, args.tag, prev), args.repo)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(notes)
    print("%d issues since %s" % (len(kept), prev or "the first commit"), file=sys.stderr)


if __name__ == "__main__":
    main()
