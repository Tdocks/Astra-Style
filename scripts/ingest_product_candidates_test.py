#!/usr/bin/env python3
"""Fixture validation for P6-SHOP-08 ingest. No network."""

from __future__ import annotations

import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from ingest_product_candidates import DEFAULT_FIXTURE, validate_fixture

REPO_ROOT = Path(__file__).resolve().parent.parent


class IngestFixtureTests(unittest.TestCase):
    def test_default_fixture_validates(self) -> None:
        rows = validate_fixture(DEFAULT_FIXTURE)
        self.assertGreaterEqual(len(rows), 3)
        urls = [row["canonical_url"] for row in rows]
        self.assertEqual(len(urls), len(set(urls)))
        for row in rows:
            self.assertIn("color", row["attributes"])
            self.assertTrue(row["canonical_url"].startswith("https://"))

    def test_sponsored_is_optional_and_boolean(self) -> None:
        rows = validate_fixture(DEFAULT_FIXTURE)
        sponsored = [row for row in rows if row["sponsored"]]
        organic = [row for row in rows if not row["sponsored"]]
        self.assertGreaterEqual(len(organic), 1)
        self.assertGreaterEqual(len(sponsored), 1)


if __name__ == "__main__":
    unittest.main()
