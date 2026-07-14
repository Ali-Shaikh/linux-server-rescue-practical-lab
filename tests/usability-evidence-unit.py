#!/usr/bin/env python3
"""Unit checks for the usability evidence parser and summary."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("usability-evidence.py")
SPEC = importlib.util.spec_from_file_location("usability_evidence", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise SystemExit("Could not load usability-evidence.py")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class MemoryParserTests(unittest.TestCase):
    def test_binary_units(self) -> None:
        self.assertEqual(MODULE.parse_memory("512KiB"), 512 * 1024)
        self.assertEqual(MODULE.parse_memory("1.5MiB"), round(1.5 * 1024**2))
        self.assertEqual(MODULE.parse_memory("2GiB"), 2 * 1024**3)

    def test_decimal_units_and_zero(self) -> None:
        self.assertEqual(MODULE.parse_memory("0B"), 0)
        self.assertEqual(MODULE.parse_memory("2.5MB"), 2_500_000)

    def test_invalid_value(self) -> None:
        with self.assertRaises(ValueError):
            MODULE.parse_memory("12 megabytes")


class SummaryTests(unittest.TestCase):
    def test_summary_reports_both_gates(self) -> None:
        summary = MODULE.render_summary(
            {
                "passed": True,
                "quick_start": {
                    "elapsed_seconds": 42.5,
                    "limit_seconds": 600,
                    "passed": True,
                },
                "resources": {
                    "peak_total_mib": 256.25,
                    "limit_mib": 4096,
                    "passed": True,
                },
            }
        )
        self.assertIn("42.5 s", summary)
        self.assertIn("256.25 MiB", summary)
        self.assertIn("Overall: **PASS**", summary)


class LimitTests(unittest.TestCase):
    def test_time_limit_boundary(self) -> None:
        self.assertTrue(MODULE.within_time_limit(600))
        self.assertFalse(MODULE.within_time_limit(600.01))

    def test_memory_limit_boundary(self) -> None:
        self.assertTrue(MODULE.within_memory_limit(4 * 1024**3))
        self.assertFalse(MODULE.within_memory_limit(4 * 1024**3 + 1))


if __name__ == "__main__":
    unittest.main()
