#!/usr/bin/env python3
"""Emit stable method-level Xcode selectors for one functional UI-test shard."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


CORE_SUITES = {
    "AstraStyleUITests",
    "ProductLinkFlowUITests",
    "LuxuryAuditUITests",
}
ONBOARDING_SUITES = {
    "OnboardingCaptureStepsUITests",
    "OnboardingFirstItemsUITests",
    "OnboardingFlowUITests",
}
SEPARATE_SUITES = {
    "PerformanceAcceptanceUITests",
    "LocalConnectedJourneyAcceptanceUITests",
    "LocalKyraAcceptanceUITests",
}
SUITE_PATTERN = re.compile(r"^\s*(?:final\s+)?class\s+(\w+)\b[^\n{]*\{", re.M)
METHOD_PATTERN = re.compile(r"^\s+func\s+(test\w+)\s*\(", re.M)


def discover_all_methods(ui_test_directory: Path) -> list[str]:
    """Return sorted Xcode selectors for every UI test method."""
    selectors: list[str] = []
    for source in sorted(ui_test_directory.glob("*.swift")):
        text = source.read_text(encoding="utf-8")
        suites = SUITE_PATTERN.findall(text)
        methods = METHOD_PATTERN.findall(text)
        if not methods:
            continue
        if len(suites) != 1:
            raise ValueError(f"Expected one XCTestCase per test source: {source.name}")
        suite = suites[0]
        selectors.extend(
            f"-only-testing:AstraStyleUITests/{suite}/{method}"
            for method in methods
        )
    return sorted(selectors)


def discover_methods(ui_test_directory: Path) -> list[str]:
    """Return sorted Xcode selectors for feature suites only."""
    reserved = CORE_SUITES | ONBOARDING_SUITES | SEPARATE_SUITES
    return [
        selector for selector in discover_all_methods(ui_test_directory)
        if selector.split("/")[1] not in reserved
    ]


def split_methods(selectors: list[str]) -> tuple[list[str], list[str]]:
    """Split stable sorted selectors into two count-balanced shards."""
    ordered = sorted(selectors)
    return ordered[::2], ordered[1::2]


def self_test() -> None:
    fixture = [
        "-only-testing:AstraStyleUITests/FeatureUITests/testAlpha",
        "-only-testing:AstraStyleUITests/FeatureUITests/testBeta",
        "-only-testing:AstraStyleUITests/FeatureUITests/testGamma",
        "-only-testing:AstraStyleUITests/FeatureUITests/testDelta",
        "-only-testing:AstraStyleUITests/FeatureUITests/testEpsilon",
    ]
    first, second = split_methods(fixture)
    if first != split_methods(fixture)[0] or second != split_methods(fixture)[1]:
        raise AssertionError("Feature shard generation is not deterministic")
    if set(first) & set(second) or set(first) | set(second) != set(fixture):
        raise AssertionError("Feature shard generation duplicated or omitted a method")
    if abs(len(first) - len(second)) > 1:
        raise AssertionError("Feature shard method counts are unbalanced")
    if any("/FeatureUITests/" not in selector for selector in first + second):
        raise AssertionError("Generator did not preserve method-level selectors")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shard", choices=("features", "features-extra"))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print("Feature selector generator checks passed.")
        return 0
    if args.shard is None:
        parser.error("provide a feature shard or --self-test")

    repo_root = Path(__file__).resolve().parents[1]
    all_methods = discover_methods(repo_root / "ios/AstraStyle/Tests/UITests")
    first, second = split_methods(all_methods)
    for selector in first if args.shard == "features" else second:
        print(selector)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, AssertionError) as error:
        print(f"Feature selector generation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
