#!/usr/bin/env python3
"""Focused unit checks for future-safe feature UI test sharding."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from ios_feature_test_selectors import discover_methods, split_methods


class FeatureSelectorTests(unittest.TestCase):
    def test_discovers_methods_and_excludes_reserved_suites(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Feature.swift").write_text(
                "final class FeatureUITests: XCTestCase {\n"
                "    func testSave() {}\n"
                "    func testRetry() {}\n"
                "}\n",
                encoding="utf-8",
            )
            (root / "Onboarding.swift").write_text(
                "final class OnboardingFlowUITests: XCTestCase {\n"
                "    func testFirstRun() {}\n"
                "}\n",
                encoding="utf-8",
            )
            (root / "Local.swift").write_text(
                "final class LocalKyraAcceptanceUITests: XCTestCase {\n"
                "    func testLocalJourney() {}\n"
                "}\n",
                encoding="utf-8",
            )

            self.assertEqual(
                discover_methods(root),
                [
                    "-only-testing:AstraStyleUITests/FeatureUITests/testRetry",
                    "-only-testing:AstraStyleUITests/FeatureUITests/testSave",
                ],
            )

    def test_split_is_stable_complete_nonoverlapping_and_balanced(self) -> None:
        methods = [f"selector-{index:02d}" for index in range(31)]
        first, second = split_methods(methods)
        self.assertEqual((first, second), split_methods(methods))
        self.assertEqual(set(methods), set(first) | set(second))
        self.assertFalse(set(first) & set(second))
        self.assertLessEqual(abs(len(first) - len(second)), 1)


if __name__ == "__main__":
    unittest.main()
