"""Tests for the scripts that guard the repo: the PR checklist, the coverage ratchet and the runner guard.

    python3 -m unittest discover -s app/tests/Scripts

A gate nobody tested is a gate that either lets everything through or blocks the next honest PR, so
both are exercised here on the shapes they meet in CI. Standard library only, like the scripts.
"""
import html
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
close_release_issue = load("close-release-issue")
refresh_evidence = load("refresh-evidence")

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


class LocalSignIdentityTests(unittest.TestCase):
    """`Scripts/local-sign-identity.sh`: a build from source is signed so the keychain keeps trusting it (#242)."""

    def identity(self, listing, override=None):
        bin_dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, bin_dir)
        with open(os.path.join(bin_dir, "security"), "w", encoding="utf-8") as handle:
            handle.write("#!/bin/sh\ncat <<'LIST'\n" + listing + "\nLIST\n")
        os.chmod(os.path.join(bin_dir, "security"), 0o700)
        env = dict(os.environ, PATH=bin_dir + os.pathsep + os.environ.get("PATH", ""))
        env.pop("CELLAR_LOCAL_SIGN_IDENTITY", None)
        if override is not None:
            env["CELLAR_LOCAL_SIGN_IDENTITY"] = override
        script = os.path.join(ROOT, "Scripts", "local-sign-identity.sh")
        result = subprocess.run(["sh", "-c", f'. "{script}" >/dev/null; printf %s "$LOCAL_SIGN_IDENTITY"'],
                                env=env, capture_output=True, text=True, check=True)
        return result.stdout

    DEV = "A" * 40
    LISTING = (f'  1) {"B" * 40} "Developer ID Application: Kenneth (TEAM123456)"\n'
               f'  2) {DEV} "Apple Development: kenneth@example.com (TEAM123456)"\n'
               "     2 valid identities found")

    def test_an_apple_development_identity_is_used(self):
        self.assertEqual(self.identity(self.LISTING), self.DEV, "never ad-hoc when the Mac has one, never Developer ID")

    def test_no_identity_falls_back_to_ad_hoc(self):
        self.assertEqual(self.identity("     0 valid identities found"), "-")

    def test_an_override_wins(self):
        self.assertEqual(self.identity(self.LISTING, override="-"), "-")

    def test_the_installer_signs_the_cli_with_its_stable_identifier(self):
        with open(os.path.join(ROOT, "Scripts", "install-app.sh"), encoding="utf-8") as handle:
            script = handle.read()
        self.assertIn(". Scripts/local-sign-identity.sh", script)
        self.assertIn('local_sign .build/release/cellar "$CELLAR_CLI_IDENTIFIER"', script)


class RegressionLedgerTests(unittest.TestCase):
    """`docs/REGRESSIONS.md`: every fixed bug names a test, and that test exists (Kenneth, 2026-11-02)."""

    def test_every_listed_test_exists(self):
        import re
        with open(os.path.join(os.path.dirname(ROOT), "docs", "REGRESSIONS.md"), encoding="utf-8") as handle:
            rows = [line for line in handle if re.match(r"^\| #\d+ ", line)]
        self.assertGreater(len(rows), 10)
        tests = os.path.join(ROOT, "tests")
        for row in rows:
            found = re.search(r"`([\w+.-]+\.(?:swift|py|c))` › `(\w+)`", row)
            self.assertIsNotNone(found, f"no test named in: {row.strip()}")
            name, func = found.groups()
            paths = [os.path.join(d, name) for d, _, files in os.walk(tests) if name in files]
            self.assertTrue(paths, f"{name} not found under app/tests")
            pattern = {".py": f"def {func}(", ".c": f" {func}("}.get(os.path.splitext(name)[1], f"func {func}(")
            with open(paths[0], encoding="utf-8") as handle:
                self.assertIn(pattern, handle.read(), f"{name} has no {func}: {row.strip()}")


class MakeDmgRetryTests(unittest.TestCase):
    """`make-dmg.sh` rides out a busy disk-image helper instead of failing the release (#347)."""

    SCRIPT = os.path.join(ROOT, "Scripts", "make-dmg.sh")

    def _run(self, failures):
        with open(self.SCRIPT, encoding="utf-8") as handle:
            source = handle.read()
        start = source.index("retry_hdiutil() {")
        function = source[start:source.index("\n}\n", start) + 3]
        with tempfile.TemporaryDirectory() as tmp:
            fake = os.path.join(tmp, "hdiutil")
            count = os.path.join(tmp, "count")
            with open(fake, "w", encoding="utf-8") as handle:
                handle.write(f"""#!/bin/sh
n=$(cat "{count}" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "{count}"
[ "$n" -gt {failures} ] || {{ echo "hdiutil: create failed - Resource busy" >&2; exit 1; }}
""")
            os.chmod(fake, 0o700)
            script = "sleep() { :; }\n" + function + "retry_hdiutil create -ov x.dmg\n"
            result = subprocess.run(["sh", "-c", script], env={**os.environ, "PATH": f"{tmp}:{os.environ['PATH']}"},
                                    capture_output=True, text=True)
            with open(count, encoding="utf-8") as handle:
                return result.returncode, int(handle.read())

    def test_busy_disk_is_retried(self):
        self.assertEqual(self._run(failures=2), (0, 3))

    def test_gives_up_eventually(self):
        code, calls = self._run(failures=99)
        self.assertNotEqual(code, 0)
        self.assertEqual(calls, 5)

    def test_create_and_convert_use_it(self):
        with open(self.SCRIPT, encoding="utf-8") as handle:
            source = handle.read()
        self.assertIn("retry_hdiutil create ", source)
        self.assertIn("retry_hdiutil convert ", source)
        self.assertNotIn("\nhdiutil create ", source)


class CloseReleaseIssueTests(unittest.TestCase):
    """The release workflow closes the issue that asked for the release (0.4.1 and 0.4.2 stayed open)."""

    def issue(self, number, title, state="open", **extra):
        return dict(number=number, title=title, state=state, **extra)

    def test_closes_this_versions_release_issue(self):
        issues = [
            self.issue(275, "Release Cellar 0.6.0"),
            self.issue(276, "Bump Cellar to 0.6.0"),
            self.issue(211, "Add a verify report to every game"),
        ]
        self.assertEqual(close_release_issue.release_issues(issues, "0.6.0"), [275, 276])

    def test_leaves_other_versions_closed_issues_and_pull_requests(self):
        issues = [
            self.issue(198, "Release Cellar 0.4.2"),
            self.issue(300, "Release Cellar 0.6.01"),
            self.issue(301, "Release Cellar 0.6.0", state="closed"),
            self.issue(302, "Release Cellar 0.6.0", pull_request={}),
            self.issue(303, "Release Cellar 0.6.0 notes are wrong"),
        ]
        self.assertEqual(close_release_issue.release_issues(issues, "0.6.0"), [])

    def test_matches_a_v_prefix_and_case_but_not_a_regex_dot(self):
        issues = [self.issue(1, "release cellar v0.6.0"), self.issue(2, "Release Cellar 0x6x0")]
        self.assertEqual(close_release_issue.release_issues(issues, "0.6.0"), [1])

    def test_release_workflow_runs_it_after_publishing(self):
        with open(os.path.join(os.path.dirname(ROOT), ".github", "workflows", "release.yml")) as f:
            workflow = f.read()
        publish = workflow.index("gh release create")
        close = workflow.index("Scripts/close-release-issue.py")
        self.assertLess(publish, close, "the issue must close only once the release is out")
        self.assertIn("issues: write", workflow)


class EvidenceRefreshTests(unittest.TestCase):
    """refresh-evidence.py (#286): public reports into the profiles, never wiping what it can't read."""

    PROFILE = """[game]
slug          = "fixture"
steam_appid   = 42
store         = "steam"

[compatibility]
anticheat                   = "none"
status                      = "untested"        # a comment the scan must survive
notes                       = "Not yet launched."

[runner]
id              = "wineforge"
"""

    def fake(self, protondb=None, deck=None, awacy=None, fail=()):
        def fetch(url):
            if any(word in url for word in fail):
                raise OSError("unreachable")
            if "protondb" in url:
                return {"tier": protondb}
            if "deck" in url:
                return {"results": {"resolved_category": deck}}
            return awacy or []
        return fetch

    def run_on(self, fetch, text=None):
        folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, folder)
        path = os.path.join(folder, "fixture.toml")
        with open(path, "w") as handle:
            handle.write(text or self.PROFILE)
        changes = refresh_evidence.refresh(folder, fetch=fetch, today="2026-11-03")
        with open(path) as handle:
            return changes, handle.read()

    def test_writes_every_source_into_compatibility(self):
        awacy = [{"storeIds": {"steam": "42"}, "status": "Denied"}]
        changes, text = self.run_on(self.fake("gold", 3, awacy))
        fields = refresh_evidence.read_fields(text)
        self.assertEqual(fields["protondb"], "gold")
        self.assertEqual(fields["steam_deck"], "verified")
        self.assertEqual(fields["anticheat_on_linux"], "denied")
        self.assertEqual(fields["evidence_checked"], "2026-11-03")
        self.assertEqual(fields["status"], "untested", "evidence is never a status")
        self.assertIn("fixture", changes)
        # Inside [compatibility], before [runner].
        self.assertLess(text.index("protondb"), text.index("[runner]"))
        self.assertGreater(text.index("protondb"), text.index("[compatibility]"))

    def test_a_source_that_fails_keeps_its_value(self):
        _, first = self.run_on(self.fake("gold", 3))
        changes, text = self.run_on(self.fake("borked", 1, fail=("protondb",)), first)
        fields = refresh_evidence.read_fields(text)
        self.assertEqual(fields["protondb"], "gold")
        self.assertEqual(fields["steam_deck"], "unsupported")
        self.assertEqual(changes["fixture"], {"steam_deck": ("verified", "unsupported")})

    def test_nothing_new_rewrites_nothing(self):
        _, first = self.run_on(self.fake("gold", 3))
        changes, text = self.run_on(self.fake("gold", 3), first)
        self.assertEqual(changes, {})
        self.assertEqual(text, first)

    def test_unknown_values_are_dropped(self):
        changes, text = self.run_on(self.fake("diamond", 9))
        self.assertEqual(changes, {})
        self.assertNotIn("protondb", text)

    def test_shipped_profiles_parse_like_the_app(self):
        for name in os.listdir(os.path.join(os.path.dirname(ROOT), "profiles")):
            if name.endswith(".toml"):
                with open(os.path.join(os.path.dirname(ROOT), "profiles", name)) as handle:
                    fields = refresh_evidence.read_fields(handle.read())
                self.assertIn("status", fields, name)


class MacRequirementsSiteTests(unittest.TestCase):
    """The site says which Mac each game needs (#298), and refuses to build without it."""

    @classmethod
    def setUpClass(cls):
        path = os.path.join(os.path.dirname(ROOT), "pages", "gen-site.py")
        spec = importlib.util.spec_from_file_location("gen_site", path)
        cls.site = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.site)

    def profiles(self):
        folder = os.path.join(os.path.dirname(ROOT), "profiles")
        return sorted(os.path.join(folder, name) for name in os.listdir(folder) if name.endswith(".toml"))

    def test_every_profile_names_both_macs_through_both_parsers(self):
        # tomllib in CI, the hand-rolled fallback on a Mac's system Python: both must read [mac].
        for path in self.profiles():
            for parse in (self.site._parse_toml_fallback, self.site.parse_toml):
                mac = parse(path).get("mac", {})
                for key in ("mac_minimum", "mac_recommended", "pc_requirements_source"):
                    self.assertTrue(str(mac.get(key, "")).strip(), f"{os.path.basename(path)}: no {key}")
                for key in ("mac_memory_minimum", "mac_memory_recommended"):
                    self.assertIsInstance(mac.get(key), int, f"{os.path.basename(path)}: {key} is a number of GB")

    def test_the_cards_say_needs_and_best_on(self):
        games = self.site.load_games()
        html = self.site.card(games[0])
        self.assertIn("<dt>Needs</dt>", html)
        self.assertIn("<dt>Best on</dt>", html)
        self.assertIn(games[0]["mac_rec"], html)

    def test_a_profile_without_mac_fails_the_build(self):
        with open(self.profiles()[0], encoding="utf-8") as handle:
            source = handle.read()
        without = source.split("\n[mac]")[0] + "\n"
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)
        os.makedirs(os.path.join(tmp, "profiles"))
        with open(os.path.join(tmp, "profiles", "fixture.toml"), "w", encoding="utf-8") as f:
            f.write(without)
        original = self.site.ROOT
        self.site.ROOT = tmp
        self.addCleanup(setattr, self.site, "ROOT", original)
        with self.assertRaises(SystemExit) as raised:
            self.site.load_games()
        self.assertIn("[mac]", str(raised.exception))


class HomePageTests(unittest.TestCase):
    """The home page (#313): placeholders until captures exist, and the launch steps
    it quotes are the app's own words."""

    @classmethod
    def setUpClass(cls):
        path = os.path.join(os.path.dirname(ROOT), "pages", "gen-site.py")
        spec = importlib.util.spec_from_file_location("gen_site", path)
        cls.site = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.site)

    def test_the_launch_steps_are_the_apps_own_words(self):
        # A rename in LaunchStage.swift must reach the site, or the page shows steps the app never does.
        swift = os.path.join(ROOT, "Packages", "CellarDomain", "Sources", "CellarDomain", "Launch", "LaunchStage.swift")
        with open(swift, encoding="utf-8") as handle:
            source = handle.read()
        game = self.site.LAUNCH_GAME
        for title, _detail in self.site.LAUNCH_STAGES:
            pattern = title.replace(game, "\\(context.game)").replace("Steam", "\\(context.store.displayName)")
            self.assertIn(f'"{pattern}"', source, f"{title!r} is not a LaunchStage title")

    def test_every_capture_slot_says_coming_soon_until_it_is_captured(self):
        empty = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, empty)
        original = self.site.MEDIA
        self.site.MEDIA = empty
        self.addCleanup(setattr, self.site, "MEDIA", original)
        page = self.site.render_index(self.site.load_games(), None)
        self.assertEqual(page.count("Screenshot coming soon</span>"), 1 + len(self.site.SHOTS))
        self.assertIn("Video coming soon", page)
        self.assertNotIn("<video", page)

    def test_a_capture_replaces_its_placeholder(self):
        folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, folder)
        png = (b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + (1600).to_bytes(4, "big") + (1000).to_bytes(4, "big")
               + b"\x08\x02\x00\x00\x00")
        with open(os.path.join(folder, "library.png"), "wb") as f:
            f.write(png)
        original = self.site.MEDIA
        self.site.MEDIA = folder
        self.addCleanup(setattr, self.site, "MEDIA", original)
        page = self.site.render_index(self.site.load_games(), None)
        self.assertIn('src="media/library.png" width="1600" height="1000"', page)
        self.assertEqual(page.count("Screenshot coming soon</span>"), len(self.site.SHOTS))

    def test_sponsoring_never_shows_a_button_that_leads_nowhere(self):
        # #299: until there is a payment account, both pages say so instead of a dead button, and
        # the home page only points at the sponsor page (one switch: SPONSOR_LINKS).
        self.assertEqual(self.site.SPONSOR_LINKS, [])
        games = self.site.load_games()
        for page in (self.site.render_index(games, None), self.site.render_sponsor(games, None)):
            self.assertIn("Sponsoring Opens Soon", page)
            self.assertNotIn('href=""', page)
        self.assertIn('href="sponsor.html"', self.site.render_index(games, None))

    def test_sponsor_page_shows_the_payment_links_once_they_exist(self):
        links = [("Sponsor on GitHub", "https://github.com/sponsors/example")]
        original = self.site.SPONSOR_LINKS
        self.site.SPONSOR_LINKS = links
        self.addCleanup(setattr, self.site, "SPONSOR_LINKS", original)
        page = self.site.render_sponsor(self.site.load_games(), None)
        self.assertIn('href="https://github.com/sponsors/example"', page)
        self.assertNotIn("Sponsoring Opens Soon", page)
        self.assertIn("Nothing is locked", page)

    def test_every_test_mac_bought_is_listed(self):
        original = self.site.TEST_MACS_BOUGHT
        self.site.TEST_MACS_BOUGHT = [("MacBook Air", "M1", "€430", "2026-12")]
        self.addCleanup(setattr, self.site, "TEST_MACS_BOUGHT", original)
        page = self.site.render_sponsor(self.site.load_games(), None)
        self.assertIn("<td>MacBook Air</td><td>M1</td><td>€430</td><td>2026-12</td>", page)
        self.assertNotIn("Nothing yet.", page)

    def test_every_game_has_a_page_the_list_links_to(self):
        # docs/SITE-DESIGN.md §11-12: a page per game, so "<game> on Mac" finds it.
        games = self.site.load_games()
        for g in games:
            self.assertIn(f'href="games/{g["slug"]}.html"', self.site.card(g))
            page = self.site.render_game(g, games, None)
            self.assertEqual(page.count("<h1"), 1)
            self.assertIn(f"{html.escape(g['name'])} on Mac</h1>", page)
            self.assertIn('"@type": "VideoGame"', page)
            self.assertIn(g["mac_min"], page)

    def test_an_untested_game_says_so_on_its_page(self):
        games = self.site.load_games()
        untested = next(g for g in games if g["status"] == "untested")
        page = self.site.render_game(untested, games, None)
        self.assertIn("nobody has confirmed it plays yet", page)

    def test_the_home_page_shows_ten_games_and_the_games_page_all(self):
        # Kenneth, 2026-11-03: one component, ten on the home page, every game on games.html.
        games = self.site.load_games()
        home = self.site.render_index(games, None)
        self.assertEqual(home.count('class="card"'), self.site.GAMES_CAP)
        self.assertIn('action="games.html"', home)
        self.assertIn(f'href="games.html">See all {len(games)} games', home)
        self.assertNotIn("GAMES_JS", home)
        self.assertEqual(self.site.render_games(games, None).count('class="card"'), len(games))
