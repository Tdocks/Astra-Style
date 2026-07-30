#!/usr/bin/env python3
"""Fail the build on UI conventions that keep regressing.

Three rules. The first two were violated in shipped-looking code and caught
only because someone looked at a screenshot. The third is here BEFORE its
feature ships, because it is the one whose violation would be hardest to
notice and most damaging.

1. NO "AI SPARKLE". `sparkles`, `sparkle`, `wand.and.stars`, `wand.and.rays`
   are the visual shorthand every AI product reaches for. Astra Style is a
   stylist, not a magic trick — spec §3's visual principle is "technology
   remains invisible", and a wand glyph is technology waving at the user.
   Kyra's presence is the brand mark (`AstraMonogram`), not a sparkle.

2. NO INTERNAL TICKET IDs IN USER-FACING STRINGS. Placeholder screens shipped
   copy reading "...lands here under the P3-CLOSET tickets." That is a project
   management artifact rendered to a paying customer. Placeholder copy should
   describe what the screen is for, in the product's voice.

3. THE GARMENT IS THE SUBJECT, NEVER THE BODY. Spec §2 forbids shaming body
   type, and `docs/14-frame-fit.md` §4 turns that into copy that a machine can
   check: fit advice describes what the clothing does, not what the wearer's
   body is. "A straight leg balances the shoulder line" is fine. "Skinny jeans
   don't suit your build" is not, and neither is any sentence whose subject is
   the reader's body.

   "Flattering" is banned outright. It is a euphemism for concealment and
   every reader hears it that way; it implies something needed hiding. Say
   what the garment does instead — balances, lengthens, defines, softens.

   This rule exists in tooling rather than in a style guide because a tone
   guarantee that lives only in a document does not survive a year of new
   strings written by whoever is on the ticket. There will be hundreds of
   these strings, they will be written quickly, and "flattering" is the single
   most natural word to reach for.

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

# Phrases that make the wearer's body the subject of the sentence, or that use
# concealment language. Matched anywhere in a source line rather than only
# inside string literals: a doc comment proposing this phrasing is how it ends
# up in the next string somebody writes.
BODY_LANGUAGE = [
    (r"\bflatter(?:ing|s|ed)?\b",
     "'flattering' is a euphemism for concealment. Say what the garment does "
     "— balances, lengthens, defines, softens."),
    (r"\byour (?:build|body type|body shape|figure|frame)\b",
     "makes the wearer's body the subject. Describe the garment instead."),
    (r"\bfor (?:someone|a man|men) your (?:size|build|height|shape)\b",
     "compares the wearer to other bodies. Describe the garment instead."),
    (r"\bdespite your\b",
     "frames the wearer's body as an obstacle."),
    # Requires the POSSESSIVE. "hide your stomach" is the failure mode; "hides
    # the fact that" and "hiding the ranking stage" are ordinary English about
    # something other than a body. Matching "the" as well produced three false
    # positives on the first feature written after this rule landed, all of them
    # in comments explaining the rule itself — and a checker that cries wolf on
    # its own documentation is one people learn to skip.
    (r"\b(?:hide|hides|hiding|conceal|conceals|disguise|disguises)\s+your\b",
     "concealment framing. Astra does not tell a man to hide part of himself."),
    (r"\bslimming\b|\bmakes you look (?:taller|slimmer|thinner|bigger)\b",
     "describes an effect on the body rather than on the line of the clothing."),
]
BODY_LANGUAGE_RULES = [(re.compile(p, re.IGNORECASE), why) for p, why in BODY_LANGUAGE]

# A line may opt out with a trailing `ui-conventions:allow` marker. The only
# legitimate use is a comment that must QUOTE a banned phrase in order to
# explain why it is banned — the rule table's header does exactly that, and a
# checker that forces the documentation of a rule to omit the rule is a
# checker that makes the codebase worse. The marker is deliberately ugly and
# deliberately greppable: `grep -rn "ui-conventions:allow"` should return a
# short list that is easy to audit, and any use of it on a line that is not a
# comment should be treated as a mistake in review.
ALLOW_MARKER = "ui-conventions:allow"


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

            # Body-subject language is checked in comments TOO, unlike ticket
            # ids. A ticket id in a comment is harmless; a doc comment that
            # models the wrong phrasing is a template the next person copies.
            if ALLOW_MARKER not in line and "check_ui_conventions" not in line:
                for pattern, why in BODY_LANGUAGE_RULES:
                    if pattern.search(line):
                        violations.append(
                            f"{rel}:{n}: {why}\n      {stripped}"
                        )
                        break

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
            "\nThe sparkle and ticket-id rules exist because those shipped once "
            "and were\ncaught by eye rather than by tooling. The body-language "
            "rule is here before\nits feature ships, because copy that shames a "
            "user reads as fine to the\nperson writing it — that is exactly why "
            "it needs a machine to catch it.\nSee docs/14-frame-fit.md §4."
        )
        return 1

    print(f"UI conventions OK — checked {len(relevant_files())} Swift files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
