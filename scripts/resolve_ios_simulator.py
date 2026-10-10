#!/usr/bin/env python3
# =============================================================================
# scripts/resolve_ios_simulator.py — resolve an available iPhone simulator.
# =============================================================================
# CI used to pass `-destination 'platform=iOS Simulator,name=iPhone 16'`. That
# worked until the runner image moved to macos-26, which ships the iPhone 17
# family, 17e and Air — and no iPhone 16 at all. The build died with "Unable to
# find a device matching the provided destination specifier", which reads like a
# broken workflow rather than what it was: a hardcoded model that Apple retired.
#
# The default remains a newest-runtime choice for general build/test use. Some
# screenshot baselines are device- and runtime-sensitive, so those callers can
# request an exact runtime and/or device with --runtime and --device.
#
# Prints a UDID on stdout, which is what the caller should pass as
# `-destination "id=$UDID"`. A UDID rather than a name because names are not
# unique: a runner with iOS 26.2, 26.4.1 and 26.5 installed has three devices
# called "iPhone 17", and `name=iPhone 17` leaves xcodebuild to pick among them.
#
# Default selection is the newest installed iOS runtime, then the
# alphabetically first iPhone on it. Explicit selectors never fall back: a
# missing requested runtime/device is an actionable error with the available
# inventory.
#
# Exits non-zero with the full device list on stderr when there is no iPhone at
# all, rather than letting xcodebuild fail later with a vaguer message and no
# context about what the runner actually had.
#
# Local use is the same command CI runs:
#     python3 scripts/resolve_ios_simulator.py
# =============================================================================

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys


def runtime_version(identifier: str) -> tuple[int, ...]:
    """Sort key for a runtime identifier.

    `com.apple.CoreSimulator.SimRuntime.iOS-26-5` -> `(26, 5)`, so 26.10 would
    sort above 26.5 rather than below it as a string compare would have it.
    """
    tail = identifier.rsplit(".", 1)[-1]
    return tuple(int(part) for part in tail.split("-")[1:] if part.isdigit())


def parse_requested_runtime(value: str) -> tuple[int, ...]:
    if not re.fullmatch(r"\d+(?:\.\d+)*", value):
        raise argparse.ArgumentTypeError("runtime must be a dotted version such as 26.5")
    return tuple(int(part) for part in value.split("."))


class SelectionError(ValueError):
    pass


def available_iphones(devices_by_runtime: dict) -> list[tuple[tuple[int, ...], dict]]:
    result = []
    for runtime, devices in devices_by_runtime.items():
        if "SimRuntime.iOS-" not in runtime:
            continue
        version = runtime_version(runtime)
        for device in devices:
            if device.get("name", "").startswith("iPhone"):
                result.append((version, device))
    return result


def describe_available(devices_by_runtime: dict) -> str:
    iphones = available_iphones(devices_by_runtime)
    if not iphones:
        return "No available iPhone simulators were reported."
    lines = ["Available iPhone simulators:"]
    for version, device in sorted(iphones, key=lambda entry: (entry[0], entry[1].get("name", ""))):
        lines.append(
            f"  iOS {'.'.join(map(str, version))}: "
            f"{device.get('name', '<unnamed>')} ({device.get('udid', 'no UDID')})"
        )
    return "\n".join(lines)


def select_device(
    devices_by_runtime: dict,
    requested_runtime: tuple[int, ...] | None = None,
    requested_device: str | None = None,
) -> tuple[tuple[int, ...], dict]:
    iphones = available_iphones(devices_by_runtime)
    candidates = [
        entry
        for entry in iphones
        if (requested_runtime is None or entry[0] == requested_runtime)
        and (requested_device is None or entry[1].get("name") == requested_device)
    ]
    if not candidates:
        requested = []
        if requested_runtime is not None:
            requested.append(f"iOS {'.'.join(map(str, requested_runtime))}")
        if requested_device is not None:
            requested.append(f"device {requested_device!r}")
        raise SelectionError(
            f"No available iPhone simulator matches {' and '.join(requested) or 'the request'}.\n"
            f"{describe_available(devices_by_runtime)}"
        )

    if requested_runtime is None:
        selected_version = max(entry[0] for entry in candidates)
    else:
        selected_version = requested_runtime
    same_runtime = [entry for entry in candidates if entry[0] == selected_version]
    return min(same_runtime, key=lambda entry: entry[1].get("name", ""))


def self_test() -> None:
    fixture = {
        "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
            {"name": "iPhone 17 Pro", "udid": "pro-265"},
            {"name": "iPhone 17", "udid": "phone-265"},
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
            {"name": "iPhone 18", "udid": "phone-270"},
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-26-5-beta": [
            {"name": "iPad Pro", "udid": "ipad-265"},
        ],
    }
    assert select_device(fixture) == ((27, 0), {"name": "iPhone 18", "udid": "phone-270"})
    assert select_device(fixture, (26, 5), "iPhone 17 Pro") == (
        (26, 5), {"name": "iPhone 17 Pro", "udid": "pro-265"}
    )
    assert select_device(fixture, (26, 5))[1]["udid"] == "phone-265"
    assert select_device(fixture, None, "iPhone 17 Pro")[0] == (26, 5)
    for runtime, device in [
        ((26, 4), "iPhone 17 Pro"),
        ((26, 5), "iPhone 16"),
        (None, "iPhone 16"),
    ]:
        try:
            select_device(fixture, runtime, device)
        except SelectionError as error:
            assert "Available iPhone simulators:" in str(error)
        else:
            raise AssertionError("missing explicit selection unexpectedly fell back")


def main() -> int:
    parser = argparse.ArgumentParser(description="Resolve an available iPhone simulator UDID.")
    parser.add_argument(
        "--runtime", type=parse_requested_runtime, help="exact iOS runtime version, e.g. 26.5"
    )
    parser.add_argument("--device", help="exact simulator name, e.g. 'iPhone 17 Pro'")
    parser.add_argument("--self-test", action="store_true", help="run pure simulator-selection checks")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print("Simulator selection self-test passed.")
        return 0

    try:
        raw = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "available", "--json"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    except FileNotFoundError:
        print("xcrun not found — is this a machine with Xcode installed?", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        print(f"`simctl list` failed: {error.stderr.strip()}", file=sys.stderr)
        return 1

    devices_by_runtime = json.loads(raw).get("devices", {})

    try:
        version, device = select_device(devices_by_runtime, args.runtime, args.device)
    except SelectionError as error:
        print(str(error), file=sys.stderr)
        return 1

    pretty = ".".join(str(part) for part in version)
    print(f"Selected {device['name']} on iOS {pretty} ({device['udid']})", file=sys.stderr)
    print(device["udid"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
