#!/usr/bin/env python3
"""
Unit tests for the branch-selection logic used by `tests/ci/cherry_pick.py`.

These tests pin down the backport contract directly:
  * general backports include every release branch;
  * `pr-must-backport-force` also includes every release branch;
  * version-specific labels still expand from the floor release forward.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cherry_pick_branches import select_backport_branches

MUST_BACKPORT = "pr-must-backport"
MUST_BACKPORT_FORCE = "pr-must-backport-force"
AUTO_BACKPORT = "pr-critical-bugfix"


class TestSelectBackportBranches(unittest.TestCase):
    def setUp(self):
        self.release_branches = [
            "release/25.8",
            "release/25.9",
            "release/25.10",
        ]

    def test_general_backport_includes_all_release_branches(self):
        self.assertEqual(
            select_backport_branches(
                [MUST_BACKPORT],
                self.release_branches,
                general_backport_labels={MUST_BACKPORT, AUTO_BACKPORT},
                force_backport_label=MUST_BACKPORT_FORCE,
            ),
            self.release_branches,
        )

    def test_force_backport_includes_all_release_branches(self):
        self.assertEqual(
            select_backport_branches(
                [MUST_BACKPORT_FORCE],
                self.release_branches,
                general_backport_labels={MUST_BACKPORT, AUTO_BACKPORT},
                force_backport_label=MUST_BACKPORT_FORCE,
            ),
            self.release_branches,
        )

    def test_version_specific_backport_starts_from_floor(self):
        self.assertEqual(
            select_backport_branches(
                ["v25.9-must-backport"],
                self.release_branches,
                general_backport_labels={MUST_BACKPORT, AUTO_BACKPORT},
                force_backport_label=MUST_BACKPORT_FORCE,
            ),
            ["release/25.9", "release/25.10"],
        )


if __name__ == "__main__":
    unittest.main()
