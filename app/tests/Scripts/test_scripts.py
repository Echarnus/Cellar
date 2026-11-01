"""Tests for the Python that guards the repo: the PR checklist and the coverage ratchet.

    python3 -m unittest discover -s app/tests/Scripts

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

## Delivery checklist

- [x] A1 proven: report linked above
- [ ] G4 stays-up: n/a: this changes no launch path
- [ ] P5 responsive — n/a: no screen changes in this PR

## Notes for the release
"""


class PRChecklistTests(unittest.TestCase):
    def test_a_complete_pr_passes(self):
        self.assertEqual(check_pr.problems(GOOD, ["app/Packages/CellarData/Sources/CellarData/Game.swift", "app/tests/CellarDataTests/X.swift"]), [])

    def test_code_is_the_executables_and_every_library_package(self):
        self.assertTrue(check_pr.touches_code(["app/src/CellarApp/App/AppModel.swift"]))
        self.assertTrue(check_pr.touches_code(["app/Packages/CellarUI/Sources/CellarUI/StoreMark.swift"]))
        self.assertFalse(check_pr.touches_code(["app/Packages/CellarData/Package.swift", "pages/gen-site.py"]))
        self.assertTrue(check_pr.touches_tests(["app/Packages/CellarData/Tests/CellarDataTests/X.swift"]))
        self.assertFalse(check_pr.touches_tests(["app/Packages/CellarData/Sources/CellarData/X.swift"]))

    def test_the_untouched_template_fails_on_every_count(self):
        with open(os.path.join(os.path.dirname(ROOT), ".github", "pull_request_template.md"), encoding="utf-8") as handle:
            template = handle.read()
        found = check_pr.problems(template, ["app/Packages/CellarData/Sources/CellarData/Game.swift"])
        self.assertEqual(len(found), 4, found)
        self.assertTrue(any("A1 proven" in f and "P5 responsive" in f for f in found), found)

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
        files = ["app/Packages/CellarData/Sources/CellarData/Game.swift"]
        self.assertTrue(check_pr.problems(GOOD, files))
        self.assertTrue(check_pr.problems(GOOD + "\nNo tests needed: n/a\n", files))
        self.assertEqual(check_pr.problems(
            GOOD + "\nNo tests needed: only rewords a doc comment, no code changes.\n", files), [])

    def test_non_swift_changes_do_not_need_tests(self):
        self.assertEqual(check_pr.problems(GOOD, ["docs/TESTING.md", "profiles/witcher-3.toml"]), [])

    def test_the_delivery_checklist_is_answered_for_anything_a_player_gets(self):
        for path in ("app/src/CellarApp/App/AppModel.swift", "profiles/witcher-3.toml", "app/Shim/cellar-dock-shim.c"):
            self.assertTrue(check_pr.touches_delivery([path]), path)
        self.assertFalse(check_pr.touches_delivery(["docs/TESTING.md", ".github/workflows/ci.yml", "pages/gen-site.py"]))
        body = GOOD[:GOOD.index("## Delivery checklist")] + "## Notes for the release\n"
        found = check_pr.problems(body, ["profiles/witcher-3.toml"])
        self.assertTrue(any("## Delivery checklist" in f for f in found), found)
        self.assertEqual(check_pr.problems(body, ["docs/TESTING.md"]), [])

    def test_an_unticked_delivery_line_needs_a_real_reason(self):
        files = ["profiles/witcher-3.toml"]
        for line in ("- [ ] G4 stays-up", "- [ ] G4 stays-up: n/a:", "- [ ] G4 stays-up: n/a: no"):
            body = GOOD.replace("- [ ] G4 stays-up: n/a: this changes no launch path", line)
            found = check_pr.problems(body, files)
            self.assertEqual(len(found), 1, (line, found))
            self.assertIn("G4 stays-up is unticked", found[0])
        self.assertEqual(check_pr.problems(GOOD, files), [])

    def test_a_delivery_checklist_without_boxes_fails(self):
        body = GOOD.replace("- [x] A1 proven: report linked above\n", "").replace(
            "- [ ] G4 stays-up: n/a: this changes no launch path\n", "").replace(
            "- [ ] P5 responsive — n/a: no screen changes in this PR\n", "")
        self.assertTrue(any("has no boxes" in f for f in check_pr.problems(body, ["profiles/witcher-3.toml"])))

    def test_release_notes_never_hand_players_a_command(self):
        for notes in ("Run `sh app/Scripts/restore.sh` first.", "```\ncellar repair\n```",
                      "$ xattr -dr com.apple.quarantine Cellar.app", "Paste `cd ~ && cp a b` into Terminal."):
            body = GOOD + notes + "\n"
            self.assertTrue(any("Players never need Terminal" in f for f in check_pr.problems(body, [])), notes)
        fine = GOOD + "Planet Coaster 2 shows all your DLC. The `Repairing` step takes a minute.\n"
        self.assertEqual(check_pr.problems(fine, []), [])
        # A command elsewhere in the PR (how it was verified) is evidence, not an instruction to players.
        self.assertEqual(check_pr.problems(GOOD.replace("Fixes the launch.", "Ran `sh app/Scripts/test.sh`."), []), [])

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
            (f"{ROOT}/Packages/CellarData/Sources/CellarData/Game.swift", 100, 50),
            (f"{ROOT}/Packages/CellarUI/Sources/CellarUI/StoreMark.swift", 10, 10),
            (f"{ROOT}/tests/CellarDataTests/GameTests.swift", 1000, 1000),
            (f"{ROOT}/.build/checkouts/swift-argument-parser/Sources/CellarData/Fake.swift", 1000, 0),
            (f"{ROOT}/src/cellar/Cellar.swift", 1000, 0),
        ])
        self.assertEqual((totals["CellarData"]["covered"], totals["CellarData"]["count"]), (50, 100))
        self.assertEqual(coverage.percent(totals["CellarUI"]), 100.0)

    def test_a_drop_below_the_baseline_fails(self):
        self.assertEqual(coverage.judge({"CellarDomain": 90.0, "CellarData": 50.0, "CellarUI": 80.0}, {"CellarData": 50.0, "CellarUI": 80.0}), [])
        self.assertEqual(coverage.judge({"CellarDomain": 90.0, "CellarData": 49.8, "CellarUI": 80.0}, {"CellarData": 50.0}), [],
                         "a hair under is noise between two macOS images")
        found = coverage.judge({"CellarDomain": 90.0, "CellarData": 48.0, "CellarUI": 80.0}, {"CellarData": 50.0})
        self.assertEqual(len(found), 1)
        self.assertIn("CellarData", found[0])

    def test_a_target_the_report_never_saw_fails(self):
        self.assertTrue(coverage.judge({"CellarData": 50.0}, {}))

    def test_the_committed_baseline_names_every_target(self):
        baseline = coverage.load_baseline()
        self.assertEqual(set(baseline), set(coverage.TARGETS))


if __name__ == "__main__":
    unittest.main()
