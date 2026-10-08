#!/usr/bin/env python3
"""Self-test and apply Astra's first-party compiler-warning gate."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


FIRST_PARTY_WARNING = re.compile(r"^(?:/.*/ios/)?AstraStyle/.*warning:")


def is_first_party_warning(line: str) -> bool:
    return FIRST_PARTY_WARNING.search(line) is not None


def self_test(repo_root: Path) -> int:
    fixture_lines = [
        "/runner/work/Astra-Style/Astra-Style/ios/AstraStyle/Sample.swift:1:1: warning: probe",
        "/runner/work/Astra-Style/Astra-Style/ios/SourcePackages/Foo.swift:1:1: warning: dependency",
        "/runner/work/Astra-Style/Astra-Style/ios/AstraStyleTests/Sample.swift:1:1: warning: test target",
    ]
    if not is_first_party_warning(fixture_lines[0]):
        print("::error::Warning-gate self-test failed to catch a first-party warning.")
        return 1
    if any(is_first_party_warning(line) for line in fixture_lines[1:]):
        print("::error::Warning-gate self-test incorrectly caught a dependency or test-target warning.")
        return 1
    if not is_first_party_warning("AstraStyle/AstraTheme.swift:35:43: warning: macro probe"):
        print("::error::Warning-gate self-test missed a relative macro diagnostic.")
        return 1

    command = [
        "swiftlint",
        "lint",
        "--config",
        str(repo_root / ".swiftlint.yml"),
        "--strict",
        "--only-rule",
        "trailing_whitespace",
        "--use-stdin",
    ]
    result = subprocess.run(
        command,
        cwd=repo_root,
        input="let deliberateViolation = 1  \n",
        text=True,
        capture_output=True,
        check=False,
    )
    output = result.stdout + result.stderr
    if result.returncode == 0 or "trailing_whitespace" not in output:
        print("::error::SwiftLint negative self-test did not reject a deliberate violation.")
        if output:
            print(output, file=sys.stderr)
        return 1

    print("CI gate self-test passed: strict SwiftLint rejects a known violation, and the build-warning gate scopes paths correctly.")
    return 0


def check_build_log(log_path: Path) -> int:
    try:
        lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as error:
        print(f"::error::Could not read Xcode build log: {error}")
        return 1

    warnings = [line for line in lines if is_first_party_warning(line)]
    if warnings:
        print("::error::Compiler warnings in first-party code (Phase 1 requires zero):")
        for warning in warnings:
            print(warning)
        return 1

    print("No warnings in first-party code.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--self-test", action="store_true")
    mode.add_argument("--build-log", type=Path)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    if args.self_test:
        return self_test(repo_root)
    return check_build_log(args.build_log)


if __name__ == "__main__":
    raise SystemExit(main())
