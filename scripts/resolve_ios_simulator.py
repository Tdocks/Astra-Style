#!/usr/bin/env python3
# =============================================================================
# scripts/resolve_ios_simulator.py — pick an iPhone simulator, don't name one.
# =============================================================================
# CI used to pass `-destination 'platform=iOS Simulator,name=iPhone 16'`. That
# worked until the runner image moved to macos-26, which ships the iPhone 17
# family, 17e and Air — and no iPhone 16 at all. The build died with "Unable to
# find a device matching the provided destination specifier", which reads like a
# broken workflow rather than what it was: a hardcoded model that Apple retired.
#
# A named device is a bet that Apple's simulator lineup stays still, and it
# never does. What this project actually needs from a destination is "some
# iPhone, on an iOS new enough for IPHONEOS_DEPLOYMENT_TARGET". The model
# decides nothing about whether the code compiles or the tests pass — no test in
# this repo asserts a screen size, and the AX5 walks drive Dynamic Type rather
# than device metrics. So resolve one at run time instead.
#
# Prints a UDID on stdout, which is what the caller should pass as
# `-destination "id=$UDID"`. A UDID rather than a name because names are not
# unique: a runner with iOS 26.2, 26.4.1 and 26.5 installed has three devices
# called "iPhone 17", and `name=iPhone 17` leaves xcodebuild to pick among them.
#
# Selection is the newest installed iOS runtime, then the alphabetically first
# iPhone on it. Newest runtime because that is what a developer's Xcode will
# default to, so CI and local diverge as little as possible. Alphabetically
# first only because SOMETHING has to break the tie and an arbitrary-but-stable
# rule beats a nondeterministic one — a run-to-run change in which simulator
# gets used is the kind of thing that turns a flaky test into a three-hour
# investigation.
#
# Exits non-zero with the full device list on stderr when there is no iPhone at
# all, rather than letting xcodebuild fail later with a vaguer message and no
# context about what the runner actually had.
#
# Local use is the same command CI runs:
#     python3 scripts/resolve_ios_simulator.py
# =============================================================================

from __future__ import annotations

import json
import subprocess
import sys


def runtime_version(identifier: str) -> tuple[int, ...]:
    """Sort key for a runtime identifier.

    `com.apple.CoreSimulator.SimRuntime.iOS-26-5` -> `(26, 5)`, so 26.10 would
    sort above 26.5 rather than below it as a string compare would have it.
    """
    tail = identifier.rsplit(".", 1)[-1]
    return tuple(int(part) for part in tail.split("-")[1:] if part.isdigit())


def main() -> int:
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

    best: tuple[tuple[int, ...], dict] | None = None
    for runtime, devices in devices_by_runtime.items():
        if "SimRuntime.iOS-" not in runtime:
            continue
        # `available` already filters unusable devices, but a runtime with no
        # iPhone on it (an iPad-only install) must not win the comparison.
        iphones = [d for d in devices if d.get("name", "").startswith("iPhone")]
        if not iphones:
            continue
        version = runtime_version(runtime)
        if best is None or version > best[0]:
            best = (version, sorted(iphones, key=lambda d: d["name"])[0])

    if best is None:
        print(
            "No available iPhone simulator on this machine.\n"
            "Everything simctl reported as available:",
            file=sys.stderr,
        )
        json.dump(devices_by_runtime, sys.stderr, indent=2)
        return 1

    version, device = best
    pretty = ".".join(str(part) for part in version)
    print(f"Selected {device['name']} on iOS {pretty} ({device['udid']})", file=sys.stderr)
    print(device["udid"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
