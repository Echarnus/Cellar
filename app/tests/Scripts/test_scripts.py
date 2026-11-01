"""Tests for the scripts that guard the repo: the PR checklist, the coverage ratchet and the runner guard.

    python3 -m unittest discover -s app/tests/Scripts

A gate nobody tested is a gate that either lets everything through or blocks the next honest PR, so
both are exercised here on the shapes they meet in CI. Standard library only, like the scripts.
"""
import importlib.util
import json
import os
import shutil
import subprocess
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
        files = ["app/Packages/CellarData/Sources/CellarData/Game.swift"]
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


class RunnerGuardTests(unittest.TestCase):
    """`Scripts/runner-guard.sh`: a test run that changes the real runners fails, by name (#204)."""

    def setUp(self):
        self.real = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.real)
        self.bin = os.path.join(self.real, "runners", "wineforge", "wine", "bin")
        unix = os.path.join(self.real, "runners", "wineforge", "wine", "lib", "wine", "x86_64-unix")
        os.makedirs(self.bin)
        os.makedirs(unix)
        self.write(os.path.join(self.bin, "wine"), "the real wine")
        self.write(os.path.join(self.bin, "wineserver"), "the real wineserver")
        self.write(os.path.join(unix, "ntdll.so"), "the real ntdll")
        self.write(os.path.join(unix, "user32.so"), "not guarded")
        self.snapshot = os.path.join(self.real, "before")

    @staticmethod
    def write(path, text):
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def guard(self, mode):
        env = dict(os.environ, CELLAR_REAL_HOME=self.real)
        return subprocess.run(["sh", os.path.join(ROOT, "Scripts", "runner-guard.sh"), mode, self.snapshot],
                              env=env, capture_output=True, text=True, check=False)

    def test_an_untouched_runner_passes(self):
        self.assertEqual(self.guard("snapshot").returncode, 0)
        self.assertEqual(self.guard("compare").returncode, 0)

    def test_the_190_write_fails_and_is_named(self):
        self.guard("snapshot")
        self.write(os.path.join(self.bin, "wine"), "#!/bin/sh\n# Cellar's fake Wine\nexit 0\n")
        result = self.guard("compare")
        self.assertEqual(result.returncode, 1)
        self.assertIn("wineforge/wine/bin/wine\n", result.stderr)
        self.assertNotIn("wineserver", result.stderr)

    def test_added_and_removed_files_are_named(self):
        self.guard("snapshot")
        os.remove(os.path.join(self.bin, "wineserver"))
        self.write(os.path.join(self.bin, "wine64"), "new")
        result = self.guard("compare")
        self.assertEqual(result.returncode, 1)
        self.assertIn("wineforge/wine/bin/wineserver", result.stderr)
        self.assertIn("wineforge/wine/bin/wine64", result.stderr)

    def test_files_a_runner_is_not_started_from_are_not_guarded(self):
        self.guard("snapshot")
        self.write(os.path.join(self.real, "runners", "wineforge", "wine", "lib", "wine", "x86_64-unix", "user32.so"), "x")
        self.assertEqual(self.guard("compare").returncode, 0)

    def test_a_mac_with_no_cellar_passes(self):
        shutil.rmtree(os.path.join(self.real, "runners"))
        self.assertEqual(self.guard("snapshot").returncode, 0)
        self.assertEqual(self.guard("compare").returncode, 0)

    def test_the_test_runner_uses_the_guard(self):
        with open(os.path.join(ROOT, "Scripts", "test.sh"), encoding="utf-8") as handle:
            script = handle.read()
        self.assertIn("runner-guard.sh snapshot", script)
        self.assertIn("runner-guard.sh compare", script)
        self.assertLess(script.index("runner-guard.sh snapshot"), script.index("swift test --no-parallel"))


if __name__ == "__main__":
    unittest.main()
