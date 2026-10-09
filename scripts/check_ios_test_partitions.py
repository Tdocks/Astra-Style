#!/usr/bin/env python3
"""Verify that CI partitions preserve every functional simulator UI suite."""

import re
from pathlib import Path


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    workflow = (root / ".github/workflows/ios.yml").read_text()
    arguments = {}
    for partition in ("core", "onboarding", "features"):
        match = re.search(rf"{partition}\)\s+partition_args=\((.*?)\)", workflow, re.S)
        if match is None:
            raise SystemExit(f"Missing CI partition: {partition}")
        arguments[partition] = match.group(1)

    selected = {
        partition: set(re.findall(r"-only-testing:AstraStyleUITests/(\w+)", text))
        for partition, text in arguments.items()
    }
    skipped = set(re.findall(r"-skip-testing:AstraStyleUITests/(\w+)", arguments["features"]))
    if "-only-testing:AstraStyleTests" not in arguments["core"]:
        raise SystemExit("Core partition must include all unit tests")
    if "-only-testing:AstraStyleUITests\n" not in arguments["features"]:
        raise SystemExit("Features must include future UI suites by default")
    if selected["core"] & selected["onboarding"]:
        raise SystemExit("Core and onboarding suites overlap")
    if skipped != selected["core"] | selected["onboarding"]:
        raise SystemExit("Feature exclusions must exactly match the other partitions")

    performance = "PerformanceAcceptanceUITests"
    if "-skip-testing:AstraStyleUITests/PerformanceAcceptanceUITests" not in workflow:
        raise SystemExit("Controlled performance diagnostics must stay separate")
    counts = dict.fromkeys(arguments, 0)
    for source in (root / "ios/AstraStyle/Tests/UITests").glob("*.swift"):
        text = source.read_text()
        methods = re.findall(r"^\s+func (test\w+)\(", text, re.M)
        if not methods:
            continue
        declaration = re.search(r"^(?:final )?class (\w+)\s*:", text, re.M)
        if declaration is None:
            raise SystemExit(f"Cannot identify UI suite in {source.name}")
        suite = declaration.group(1)
        if suite == performance:
            continue
        partition = next((name for name in ("core", "onboarding") if suite in selected[name]), "features")
        counts[partition] += len(methods)

    print("iOS CI functional coverage: " + ", ".join(f"{name}={count}" for name, count in counts.items()))


if __name__ == "__main__":
    main()
