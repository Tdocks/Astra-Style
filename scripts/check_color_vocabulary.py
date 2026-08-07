#!/usr/bin/env python3
"""Fail the build when iOS's colour swatches and the server's colour vocabulary drift.

ONE VOCABULARY, TWO COPIES, AND THE COPIES MUST AGREE.

`ios/.../AstraGarmentColor.swift` maps colour words to swatches so the §6.10
Style DNA palette can be *shown*. `supabase/functions/_shared/scoring/
colorVocabulary.ts` maps the same words to sRGB so the compatibility scorer can
*reason* about them. Both are keyed by the words the providers actually emit.

If they drift, the failure is quiet and nasty in a specific way: a man sees an
olive swatch on his result screen while the engine reasons about a different
olive, and every explanation the app offers him is then subtly about a garment
he is not looking at. Nothing crashes. Nothing logs. The recommendation is just
a little bit wrong forever.

Why two copies at all, rather than one generated from the other: the server
cannot import a Swift file, and generating the Swift from the TypeScript would
put a build step in front of the iOS project for a table that changes a few
times a year. A checker is the cheaper guarantee, and it is the same trade
`check_column_drift.py` already makes for the schema.

WHAT IS AND IS NOT CHECKED. Every word in one must exist in the other, and the
hex values must match exactly. The server is allowed *nothing* iOS lacks and
vice versa — an asymmetric allowance is how a table drifts one entry at a time.

Run locally:  python3 scripts/check_color_vocabulary.py
CI runs this on every PR.
"""

from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
SWIFT = REPO / "ios" / "AstraStyle" / "Core" / "DesignSystem" / "Tokens" / "AstraGarmentColor.swift"
TYPESCRIPT = REPO / "supabase" / "functions" / "_shared" / "scoring" / "colorVocabulary.ts"

# `"navy": 0x1F2A44` in Swift.
SWIFT_ENTRY = re.compile(r'"([a-z][a-z ]*)"\s*:\s*0x([0-9A-Fa-f]{6})')
# `["navy", 0x1F2A44],` in TypeScript.
TS_ENTRY = re.compile(r'\[\s*"([a-z][a-z ]*)"\s*,\s*0x([0-9A-Fa-f]{6})\s*\]')


def parse(path: pathlib.Path, pattern: re.Pattern[str]) -> dict[str, str]:
    if not path.exists():
        print(f"MISSING: {path.relative_to(REPO)}", file=sys.stderr)
        sys.exit(1)
    return {name: value.upper() for name, value in pattern.findall(path.read_text())}


def main() -> int:
    swift = parse(SWIFT, SWIFT_ENTRY)
    typescript = parse(TYPESCRIPT, TS_ENTRY)

    if not swift or not typescript:
        print("One of the vocabularies parsed as empty — the regex or the file shape changed.",
              file=sys.stderr)
        return 1

    problems: list[str] = []

    for name in sorted(set(swift) - set(typescript)):
        problems.append(
            f'"{name}" has an iOS swatch but no server entry — the scorer will read it as '
            f"an unknown colour and fall back to the 0.6 prior."
        )
    for name in sorted(set(typescript) - set(swift)):
        problems.append(
            f'"{name}" is in the server vocabulary but has no iOS swatch — the palette will '
            f"render the word with no colour beside it."
        )
    for name in sorted(set(swift) & set(typescript)):
        if swift[name] != typescript[name]:
            problems.append(
                f'"{name}" disagrees: iOS #{swift[name]}, server #{typescript[name]}. '
                f"The user would see one colour and be reasoned about with another."
            )

    if problems:
        print("Colour vocabulary drift:\n", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print(
            f"\nFix both files together:\n"
            f"  {SWIFT.relative_to(REPO)}\n"
            f"  {TYPESCRIPT.relative_to(REPO)}",
            file=sys.stderr,
        )
        return 1

    print(f"Colour vocabulary OK — {len(swift)} names agree across iOS and the scorer.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
