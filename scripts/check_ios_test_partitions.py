#!/usr/bin/env python3
"""Verify exact UI-test method coverage across normal CI partitions."""

from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

from ios_feature_test_selectors import (
    CORE_SUITES,
    ONBOARDING_SUITES,
    SEPARATE_SUITES,
    discover_all_methods,
    discover_methods,
    split_methods,
)


def branch_body(workflow: str, label_pattern: str, name: str) -> str:
    pattern = rf"^\s*{label_pattern}\)\s*(.*?)(?=^\s*[\w|-]+\)\s*|^\s*esac\s*$)"
    match = re.search(pattern, workflow, re.M | re.S)
    if match is None:
        raise SystemExit(f"Missing workflow test partition: {name}")
    return match.group(1)


def suite_selectors(body: str) -> set[str]:
    return set(re.findall(r"-only-testing:AstraStyleUITests/(\w+)(?:\s|$)", body))


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    workflow = (root / ".github/workflows/ios.yml").read_text(encoding="utf-8")
    core_body = branch_body(workflow, "core", "core")
    onboarding_body = branch_body(workflow, "onboarding", "onboarding")
    feature_body = branch_body(workflow, r"features\|features-extra", "feature shards")

    if "-only-testing:AstraStyleTests" not in core_body:
        raise SystemExit("Core partition must include all unit tests")
    if "ios_feature_test_selectors.py" not in feature_body:
        raise SystemExit("Feature shards must use the method selector generator")
    if "--shard \"${{ matrix.partition }}\"" not in feature_body:
        raise SystemExit("Feature shard generator must receive its matrix partition")
    if "features-extra" not in workflow:
        raise SystemExit("Workflow matrix must include features-extra")
    if re.search(r"^\s+options:\s*\n\s+- all\s*\n\s+- features\s*\n\s+- focused\s*$", workflow, re.M) is None:
        raise SystemExit("Manual partition selector must offer all, features and focused")
    if "inputs.partition == 'features'" not in workflow:
        raise SystemExit("Manual features choice must dispatch both feature shards")
    if "inputs.visual_only" not in workflow or "'visual'" not in workflow:
        raise SystemExit("Existing visual-only dispatch must remain available")
    if "inputs.visual_only && 'visual'" not in workflow:
        raise SystemExit("Visual-only runs need a concurrency group separate from feature runs")
    if "-skip-testing:AstraStyleUITests/PerformanceAcceptanceUITests" not in workflow:
        raise SystemExit("Controlled performance diagnostics must stay separate")

    core_suites = suite_selectors(core_body)
    onboarding_suites = suite_selectors(onboarding_body)
    if core_suites != CORE_SUITES:
        raise SystemExit(f"Core suite selection drifted: {sorted(core_suites)}")
    if onboarding_suites != ONBOARDING_SUITES:
        raise SystemExit(f"Onboarding suite selection drifted: {sorted(onboarding_suites)}")

    ui_directory = root / "ios/AstraStyle/Tests/UITests"
    all_methods = discover_all_methods(ui_directory)
    if not all_methods:
        raise SystemExit("No XCTest UI methods were discovered")
    first, second = split_methods(discover_methods(ui_directory))
    shard_counts = Counter(first + second)
    expected_features = {
        selector for selector in all_methods
        if selector.split("/")[1] not in CORE_SUITES | ONBOARDING_SUITES | SEPARATE_SUITES
    }
    if set(shard_counts) != expected_features:
        missing = sorted(expected_features - set(shard_counts))
        unexpected = sorted(set(shard_counts) - expected_features)
        raise SystemExit(f"Feature coverage mismatch; missing={missing}, unexpected={unexpected}")
    if any(count != 1 for count in shard_counts.values()):
        raise SystemExit("Every feature UI method must appear in exactly one shard")
    if set(first) & set(second):
        raise SystemExit("Feature shards overlap")
    if abs(len(first) - len(second)) > 1:
        raise SystemExit("Feature shard method counts are not balanced")

    local_runner = (root / "scripts/run_local_kyra_acceptance.py").read_text(encoding="utf-8")
    for local_suite in ("LocalConnectedJourneyAcceptanceUITests", "LocalKyraAcceptanceUITests"):
        if local_suite not in local_runner:
            raise SystemExit(f"Local acceptance suite is not explicitly selected: {local_suite}")
    if any(selector.split("/")[1] in SEPARATE_SUITES for selector in first + second):
        raise SystemExit("Performance and local acceptance methods must not enter feature shards")

    print(
        "iOS CI functional method coverage: "
        f"core suites={len(core_suites)}, onboarding suites={len(onboarding_suites)}, "
        f"features={len(first)}, features-extra={len(second)}, "
        "performance/local acceptance separate"
    )


if __name__ == "__main__":
    main()
