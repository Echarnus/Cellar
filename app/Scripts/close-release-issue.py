#!/usr/bin/env python3
"""Close the issue that asked for a release once that release is published.

    python3 Scripts/close-release-issue.py --repo Echarnus/Cellar --version 0.6.0 --tag v0.6.0

Every release starts as an issue ("Release Cellar 0.6.0", or "Bump Cellar to 0.6.0"), and the PR that
bumps the version does not always close it: 0.4.1 and 0.4.2 stayed open after they shipped. The
release workflow runs this right after `gh release create`, so the issue closes when, and only when,
the version is really out. It closes open issues whose title names exactly this version, as
completed, with a comment linking the release. Nothing open is not a failure.

Runs in the release workflow with GH_TOKEN set; needs the `gh` CLI.
Stdlib only, Python 3.9 floor (skills/python.md).
"""
import argparse
import json
import re
import subprocess
import sys

FOOTER = "\n\n---\n_Closed by the release workflow._"


def title_pattern(version):
    """The titles a release issue is written with, for this version only (0.6.0 never matches 0.6.01)."""
    return re.compile(r"^\s*(?:release cellar|bump cellar to)\s+v?%s\s*$" % re.escape(version), re.IGNORECASE)


def release_issues(issues, version):
    """The open issues (not pull requests) that ask for this version's release."""
    pattern = title_pattern(version)
    return [
        issue["number"]
        for issue in issues
        if issue.get("state") == "open"
        and "pull_request" not in issue
        and pattern.match(issue.get("title", ""))
    ]


def gh(*args):
    return subprocess.run(("gh",) + args, check=True, capture_output=True, text=True).stdout


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args(argv)

    issues = json.loads(gh("api", "--paginate", "--slurp", "repos/%s/issues?state=open&per_page=100" % args.repo))
    numbers = release_issues([issue for page in issues for issue in page], args.version)
    if not numbers:
        print("No open release issue for %s." % args.version)
        return 0
    url = "https://github.com/%s/releases/tag/%s" % (args.repo, args.tag)
    for number in numbers:
        path = "repos/%s/issues/%d" % (args.repo, number)
        gh("api", path + "/comments", "-f", "body=Shipped as [%s](%s).%s" % (args.tag, url, FOOTER))
        gh("api", "-X", "PATCH", path, "-f", "state=closed", "-f", "state_reason=completed")
        print("Closed #%d: %s is published." % (number, args.tag))
    return 0


if __name__ == "__main__":
    sys.exit(main())
