#!/usr/bin/env python3
"""Fail the build on UI conventions that keep regressing.

Two rules, both of which were violated in shipped-looking code and only caught
because someone looked at a screenshot:

1. NO "AI SPARKLE". `sparkles`, `sparkle`, `wand.and.stars`, `wand.and.rays`
   are the visual shorthand every AI product reaches for. Astra Style is a
   stylist, not a magic trick — spec §3's visual principle is "technology
   remains invisible", and a wand glyph is technology waving at the user.
   Kyra's presence is the brand mark (`AstraMonogram`), not a sparkle.

2. NO INTERNAL TICKET IDs IN USER-FACING STRINGS. Placeholder screens shipped
   copy reading "...lands here under the P3-CLOSET tickets." That is a project
   management artifact rendered to a paying customer. Placeholder copy should
   describe what the screen is for, in the product's voice.

Run locally:  python3 scripts/check_ui_conventions.py
CI runs this on every PR (.github/workflows/ios.yml).
"""

from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
SOURCE_ROOT = REPO / "ios" / "AstraStyle"

# Tests may reference ticket IDs — they are developer-facing by definition, and
# the pending-integration suite deliberately names the phase that owns each gap.
EXEMPT_DIRS = {"Tests"}

SPARKLE = re.compile(r"\bsparkles?\b|wand\.and\.(?:stars|rays)", re.IGNORECASE)

# A ticket id (P3-CLOSET) inside a string literal. Comments are fine — the
# point is what reaches the screen, not what a developer reads in source.
TICKET_IN_STRING = re.compile(r'"[^"\n]*\bP\d-[A-Z]{2,}[^"\n]*"')


def relevant_files() -> list[pathlib.Path]:
    files = []
    for path in SOURCE_ROOT.rglob("*.swift"):
        parts = set(path.relative_to(SOURCE_ROOT).parts)
        if parts & EXEMPT_DIRS:
            continue
        files.append(path)
    return files


def main() -> int:
    violations: list[str] = []

    for path in relevant_files():
        rel = path.relative_to(REPO)
        for n, line in enumerate(path.read_text().splitlines(), 1):
            stripped = line.strip()

            if SPARKLE.search(line):
                # Allow this file's own rule description to name the thing it bans.
                if "check_ui_conventions" in line:
                    continue
                violations.append(
                    f"{rel}:{n}: banned 'AI sparkle' glyph — Kyra's mark is "
                    f"AstraMonogram, not a wand.\n      {stripped}"
                )

            if stripped.startswith("//"):
                continue
            if TICKET_IN_STRING.search(line):
                violations.append(
                    f"{rel}:{n}: internal ticket id in a user-facing string. "
                    f"Say what the screen is for instead.\n      {stripped}"
                )

    if violations:
        print(f"UI CONVENTION CHECK FAILED: {len(violations)} violation(s)\n")
        for v in violations:
            print(f"  - {v}")
        print(
            "\nBoth rules exist because these shipped once and were caught by "
            "eye, not by tooling."
        )
        return 1

    print(f"UI conventions OK — checked {len(relevant_files())} Swift files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
