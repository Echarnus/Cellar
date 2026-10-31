"""Tests for the Python that guards the repo: the PR checklist and the coverage ratchet.

    python3 -m unittest discover -s Tests/Scripts

A gate nobody tested is a gate that either lets everything through or blocks the next honest PR, so
both are exercised here on the shapes they meet in CI. Standard library only, like the scripts.
"""
import importlib.util
import json
import os
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(ROOT, "Scripts", f"{name}.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check_pr = load("check-pr")
coverage = load("coverage")

GOOD = """## What and why

Fixes the launch.

Closes #80

## How it was verified

- [x] Tests pass (`sh Scripts/test.sh`)
- [ ] Wine tiers

## Notes for the release
"""


class PRChecklistTests(unittest.TestCase):
    def test_a_complete_pr_passes(self):
        self.assertEqual(check_pr.problems(GOOD, ["Sources/CellarKit/Game.swift", "Tests/CellarKitTests/X.swift"]), [])

    def test_the_untouched_template_fails_on_every_count(self):
        with open(os.path.join(ROOT, ".github", "pull_request_template.md"), encoding="utf-8") as handle:
            template = handle.read()
        found = check_pr.problems(template, ["Sources/CellarKit/Game.swift"])
        self.assertEqual(len(found), 3, found)

    def test_an_issue_link_is_required(self):
        found = check_pr.problems(GOOD.replace("Closes #80", "See the thread."), ["README.md"])
        self.assertTrue(any("Closes #N" in f for f in found))

    def test_issue_links_in_every_spelling_github_honours(self):
        for link in ("Fixes #1", "resolves #22", "Closed #3", "Closes Echarnus/Cellar#4"):
            self.assertEqual(check_pr.problems(GOOD.replace("Closes #80", link), []), [], link)

    def test_a_link_inside_a_template_comment_does_not_count(self):
        body = GOOD.replace("Closes #80", "<!-- Closes #80 -->")
        self.assertTrue(check_pr.problems(body, []))

    def test_verification_must_tick_something(self):
        body = GOOD.replace("- [x] Tests pass", "- [ ] Tests pass")
        self.assertTrue(any("Tick what you actually ran" in f for f in check_pr.problems(body, [])))

    def test_a_tick_outside_the_verification_section_does_not_count(self):
        body = GOOD.replace("- [x] Tests pass", "- [ ] Tests pass") + "\n- [x] Unrelated\n"
        self.assertTrue(check_pr.problems(body, []))

    def test_swift_without_tests_needs_a_reason(self):
        files = ["Sources/CellarKit/Game.swift"]
        self.assertTrue(check_pr.problems(GOOD, files))
        self.assertTrue(check_pr.problems(GOOD + "\nNo tests needed: n/a\n", files))
        self.assertEqual(check_pr.problems(
            GOOD + "\nNo tests needed: only rewords a doc comment, no code changes.\n", files), [])

    def test_non_swift_changes_do_not_need_tests(self):
        self.assertEqual(check_pr.problems(GOOD, ["docs/TESTING.md", "profiles/witcher-3.toml"]), [])

    def test_dependabot_is_exempt(self):
        self.assertEqual(check_pr.problems("Bumps foo.", ["Package.resolved"], author="dependabot[bot]"), [])


def report(files):
    return {"data": [{"files": [
        {"filename": name, "summary": {"lines": {"count": count, "covered": covered}}}
        for name, count, covered in files]}]}


class CoverageTests(unittest.TestCase):
    def measure(self, files):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            json.dump(report(files), handle)
        self.addCleanup(os.unlink, handle.name)
        return coverage.measure(handle.name)

    def test_only_the_libraries_are_measured(self):
        totals = self.measure([
            (f"{ROOT}/Sources/CellarKit/Game.swift", 100, 50),
            (f"{ROOT}/Sources/CellarUI/StoreMark.swift", 10, 10),
            (f"{ROOT}/Tests/CellarKitTests/GameTests.swift", 1000, 1000),
            (f"{ROOT}/.build/checkouts/swift-argument-parser/Sources/CellarKit/Fake.swift", 1000, 0),
            (f"{ROOT}/Sources/cellar/Cellar.swift", 1000, 0),
        ])
        self.assertEqual((totals["CellarKit"]["covered"], totals["CellarKit"]["count"]), (50, 100))
        self.assertEqual(coverage.percent(totals["CellarUI"]), 100.0)

    def test_a_drop_below_the_baseline_fails(self):
        self.assertEqual(coverage.judge({"CellarDomain": 90.0, "CellarKit": 50.0, "CellarUI": 80.0}, {"CellarKit": 50.0, "CellarUI": 80.0}), [])
        self.assertEqual(coverage.judge({"CellarDomain": 90.0, "CellarKit": 49.8, "CellarUI": 80.0}, {"CellarKit": 50.0}), [],
                         "a hair under is noise between two macOS images")
        found = coverage.judge({"CellarDomain": 90.0, "CellarKit": 48.0, "CellarUI": 80.0}, {"CellarKit": 50.0})
        self.assertEqual(len(found), 1)
        self.assertIn("CellarKit", found[0])

    def test_a_target_the_report_never_saw_fails(self):
        self.assertTrue(coverage.judge({"CellarKit": 50.0}, {}))

    def test_the_committed_baseline_names_every_target(self):
        baseline = coverage.load_baseline()
        self.assertEqual(set(baseline), set(coverage.TARGETS))


if __name__ == "__main__":
    unittest.main()
