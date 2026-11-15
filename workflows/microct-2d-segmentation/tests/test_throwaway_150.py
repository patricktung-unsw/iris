"""Throwaway, reverted before merging (#150): passes in microct/1, which
has no humanize, and fails in the throwaway microct/2, which adds it, so
the containers run's report shows a failed workflow while the run is green."""

import importlib.util
import unittest


class Throwaway(unittest.TestCase):
    def test_humanize_is_not_installed(self):
        self.assertIsNone(importlib.util.find_spec("humanize"))


if __name__ == "__main__":
    unittest.main()
