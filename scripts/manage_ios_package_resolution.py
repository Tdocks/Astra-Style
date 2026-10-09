#!/usr/bin/env python3
"""Install or record Astra's reviewed SwiftPM resolution without building iOS."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parents[1]
CANONICAL = ROOT / "ios/Dependencies/AstraStyle.Package.resolved"
GENERATED = ROOT / (
    "ios/AstraStyle.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
)
PROJECT_SPEC = ROOT / "ios/project.yml"


class ResolutionError(ValueError):
    """Raised when a package lock is malformed or violates the app pin."""


def expected_supabase_version(project_text: str) -> str:
    match = re.search(
        r"(?ms)^packages:\s*\n\s+Supabase:\s*\n"
        r"\s+url:\s*https://github\.com/supabase/supabase-swift\s*\n"
        r"\s+exactVersion:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$",
        project_text,
    )
    if match is None:
        raise ResolutionError("project.yml must pin Supabase with exactVersion.")
    return match.group(1)


def validate_resolution(contents: bytes, expected_version: str) -> dict[str, object]:
    try:
        lock = json.loads(contents)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ResolutionError("Package.resolved is not valid UTF-8 JSON.") from error

    if not isinstance(lock, dict) or lock.get("version") != 3:
        raise ResolutionError("Package.resolved must use format version 3.")
    origin_hash = lock.get("originHash")
    if not isinstance(origin_hash, str) or re.fullmatch(r"[0-9a-f]{64}", origin_hash) is None:
        raise ResolutionError("Package.resolved must contain a 64-character originHash.")

    pins = lock.get("pins")
    if not isinstance(pins, list) or not pins:
        raise ResolutionError("Package.resolved must contain at least one package pin.")

    identities: set[str] = set()
    supabase_pin: dict[str, object] | None = None
    for pin in pins:
        if not isinstance(pin, dict):
            raise ResolutionError("Every package pin must be an object.")
        identity = pin.get("identity")
        location = pin.get("location")
        state = pin.get("state")
        if not isinstance(identity, str) or not identity:
            raise ResolutionError("Every package pin needs an identity.")
        if identity in identities:
            raise ResolutionError(f"Duplicate package identity: {identity}.")
        identities.add(identity)
        if not isinstance(location, str) or not location.startswith("https://"):
            raise ResolutionError(f"Package {identity} must use an HTTPS source.")
        if identity == "supabase-swift" and location != "https://github.com/supabase/supabase-swift":
            raise ResolutionError("supabase-swift must resolve from the canonical Supabase repository.")
        if not isinstance(state, dict):
            raise ResolutionError(f"Package {identity} has no resolved state.")
        revision = state.get("revision")
        version = state.get("version")
        if not isinstance(revision, str) or re.fullmatch(r"[0-9a-f]{40}", revision) is None:
            raise ResolutionError(f"Package {identity} needs a full 40-character revision.")
        if not isinstance(version, str) or not version:
            raise ResolutionError(f"Package {identity} needs a resolved version.")
        if identity == "supabase-swift":
            supabase_pin = pin

    if supabase_pin is None:
        raise ResolutionError("Package.resolved does not contain supabase-swift.")
    state = supabase_pin["state"]
    if not isinstance(state, dict):
        raise ResolutionError("The Supabase package pin has no resolved state.")
    if state.get("version") != expected_version:
        raise ResolutionError(
            f"Resolved supabase-swift {state.get('version')} does not match "
            f"project.yml exactVersion {expected_version}."
        )
    return lock


def atomic_copy(source: Path, destination: Path, expected_version: str) -> None:
    contents = source.read_bytes()
    validate_resolution(contents, expected_version)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".tmp")
    temporary.write_bytes(contents)
    temporary.replace(destination)


def run_self_test() -> None:
    expected = "2.54.0"
    project_text = (
        "packages:\n"
        "  Supabase:\n"
        "    url: https://github.com/supabase/supabase-swift\n"
        f"    exactVersion: {expected}\n"
    )
    if expected_supabase_version(project_text) != expected:
        raise ResolutionError("Self-test failed: exact Supabase version was not parsed.")

    valid = {
        "originHash": "a" * 64,
        "pins": [
            {
                "identity": "supabase-swift",
                "kind": "remoteSourceControl",
                "location": "https://github.com/supabase/supabase-swift",
                "state": {"revision": "b" * 40, "version": expected},
            },
        ],
        "version": 3,
    }
    with TemporaryDirectory() as temporary_directory:
        temporary_root = Path(temporary_directory)
        source = temporary_root / "canonical.resolved"
        destination = temporary_root / "generated/Package.resolved"
        source.write_text(json.dumps(valid), encoding="utf-8")
        atomic_copy(source, destination, expected)
        if destination.read_bytes() != source.read_bytes():
            raise ResolutionError("Self-test failed: install changed canonical contents.")

        wrong_version = json.loads(source.read_text(encoding="utf-8"))
        wrong_version["pins"][0]["state"]["version"] = "2.53.0"
        source.write_text(json.dumps(wrong_version), encoding="utf-8")
        original_destination = destination.read_bytes()
        try:
            atomic_copy(source, destination, expected)
        except ResolutionError:
            pass
        else:
            raise ResolutionError("Self-test failed: mismatched direct pin was accepted.")
        if destination.read_bytes() != original_destination:
            raise ResolutionError("Self-test failed: invalid lock changed the generated file.")

        try:
            expected_supabase_version(project_text.replace("exactVersion:", "from:"))
        except ResolutionError:
            pass
        else:
            raise ResolutionError("Self-test failed: a floating direct version was accepted.")

        duplicate = json.loads(json.dumps(valid))
        duplicate["pins"].append(duplicate["pins"][0])
        try:
            validate_resolution(json.dumps(duplicate).encode(), expected)
        except ResolutionError:
            pass
        else:
            raise ResolutionError("Self-test failed: duplicate package identity was accepted.")

        wrong_source = json.loads(json.dumps(valid))
        wrong_source["pins"][0]["location"] = "https://example.invalid/supabase-swift"
        try:
            validate_resolution(json.dumps(wrong_source).encode(), expected)
        except ResolutionError:
            pass
        else:
            raise ResolutionError("Self-test failed: a noncanonical Supabase source was accepted.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--install", action="store_true", help="copy reviewed lock into generated project")
    action.add_argument(
        "--record-reviewed-resolution",
        action="store_true",
        help="record a freshly resolved project lock after explicit review",
    )
    action.add_argument("--self-test", action="store_true", help="run dependency-free helper checks")
    parser.add_argument(
        "--reviewed",
        action="store_true",
        help="required acknowledgement when recording a new canonical graph",
    )
    args = parser.parse_args()

    try:
        if args.self_test:
            run_self_test()
            print("SwiftPM resolution helper self-test passed.")
            return 0

        expected_version = expected_supabase_version(PROJECT_SPEC.read_text(encoding="utf-8"))
        if args.install:
            atomic_copy(CANONICAL, GENERATED, expected_version)
            print(f"Installed reviewed SwiftPM resolution for Supabase {expected_version}.")
            return 0

        if not args.reviewed:
            raise ResolutionError(
                "Recording a package graph requires --reviewed after an explicit resolution review."
            )
        atomic_copy(GENERATED, CANONICAL, expected_version)
        print(f"Recorded reviewed SwiftPM resolution for Supabase {expected_version}.")
        return 0
    except (OSError, ResolutionError) as error:
        print(f"SwiftPM resolution check failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
