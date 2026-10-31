#!/usr/bin/env python3
"""Unit tests for Scripts/release-notes.py's renderer. No network, no gh, no git.

    python3 Scripts/test-release-notes.py

Stdlib only, Python 3.9 floor (skills/python.md).
"""
import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location("release_notes", os.path.join(HERE, "release-notes.py"))
notes = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(notes)

REPO = "Echarnus/Cellar"


def issue(number, title, *labels):
    return {"number": number, "title": title, "url": "https://example.test/%d" % number,
            "labels": list(labels), "completed": True}


class RenderTests(unittest.TestCase):
    def test_closed_issues_group_under_their_first_matching_section(self):
        text = notes.render("0.3.0", [issue(2, "Faster", "performance"), issue(1, "Crash", "bug")],
                            "", REPO)
        self.assertLess(text.index("## Fixes"), text.index("## Performance"))
        self.assertIn("- Crash ([#1](https://example.test/1))", text)

    def test_known_open_items_lists_waiting_issues_in_order(self):
        waiting = [{"number": 23, "title": "Workshop", "url": "https://example.test/23"},
                   {"number": 18, "title": "FPS", "url": "https://example.test/18"}]
        text = notes.render("0.3.0", [issue(1, "Crash", "bug")], "", REPO, waiting)
        section = text[text.index("## Known open items"):text.index("## Install")]
        self.assertIn(notes.OPEN_ITEMS_INTRO, section)
        self.assertLess(section.index("#18"), section.index("#23"))

    def test_known_open_items_comes_after_the_changes_and_before_install(self):
        waiting = [{"number": 18, "title": "FPS", "url": "https://example.test/18"}]
        text = notes.render("0.3.0", [issue(1, "Crash", "bug")], "## What's Changed\n* x", REPO,
                            waiting)
        self.assertLess(text.index("## Fixes"), text.index("## Known open items"))
        self.assertLess(text.index("## Known open items"), text.index("## Pull requests"))
        self.assertLess(text.index("## Pull requests"), text.index("## Install"))

    def test_no_waiting_issues_means_no_section(self):
        text = notes.render("0.3.0", [issue(1, "Crash", "bug")], "", REPO)
        self.assertNotIn("Known open items", text)

    def test_the_label_is_one_the_repository_defines(self):
        with open(os.path.join(HERE, "..", "..", ".github", "labels.yml"), encoding="utf-8") as fh:
            self.assertIn("name: %s," % notes.OPEN_ITEMS, fh.read())


if __name__ == "__main__":
    unittest.main()
