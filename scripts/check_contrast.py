#!/usr/bin/env python3
"""Fail the build when a design token pair falls below its WCAG contrast floor.

Spec §19 requires "High-contrast alternative for champagne text" and forbids
encoding meaning by colour alone. `docs/07-design-system.md` records a contrast
audit — but an audit is a snapshot. This is the same check, run every time.

It exists because of a real failure: the light palette's `accentChampagne`
(#B8914E) sits at 2.68:1 on the light background, failing WCAG AA outright.
That was documented, `accentChampagneAccessible` was added to fix it — and then
the legal links on the welcome screen used the failing token anyway. Nobody
noticed for weeks, because light mode was unreachable and so nobody ever
*looked* at it. Documentation did not prevent the bug; a build step would have.

Token values are parsed from the Swift source, not duplicated here. A table of
hex codes in a script is a second source of truth that silently goes stale.

Run locally:  python3 scripts/check_contrast.py
CI runs it on every PR (.github/workflows/ios.yml).
"""

from __future__ import annotations

import pathlib
import json
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
COLOR_FILE = REPO / "ios/AstraStyle/Core/DesignSystem/Tokens/AstraColor.swift"
COLOR_ASSET_ROOT = REPO / "ios/AstraStyle/Resources/Assets.xcassets"

# WCAG 2.1 contrast minimums.
AA_NORMAL = 4.5   # body text
AA_LARGE = 3.0    # >=18pt, or >=14pt bold — also the floor for UI components


def parse_tokens(source: str) -> dict[str, dict[str, int]]:
    """Extract `name -> {dark, light}` from AstraColor's adaptive assets."""
    tokens: dict[str, dict[str, int]] = {}

    # `AstraColor` remains the token-name source of truth; the Asset Catalog is
    # the value source of truth. Resolve the asset reference from each property
    # instead of duplicating hex values in this script.
    pattern = re.compile(
        r"static var (\w+): Color \{\s*asset\(\"([A-Za-z0-9]+)\"\)",
        re.MULTILINE,
    )
    for match in pattern.finditer(source):
        token_name, asset_name = match.groups()
        tokens[token_name] = read_adaptive_asset(asset_name)

    return tokens


def read_adaptive_asset(asset_name: str) -> dict[str, int]:
    """Read universal (light) and dark sRGB colors from a color set."""
    contents_path = COLOR_ASSET_ROOT / f"{asset_name}.colorset" / "Contents.json"
    try:
        contents = json.loads(contents_path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read {contents_path.relative_to(REPO)}: {error}") from error

    entries = contents.get("colors", [])
    light_entry = next(
        (entry for entry in entries if "appearances" not in entry and entry.get("idiom") == "universal"),
        None,
    )
    dark_entry = next(
        (
            entry for entry in entries
            if entry.get("idiom") == "universal"
            and any(
                appearance.get("appearance") == "luminosity"
                and appearance.get("value") == "dark"
                for appearance in entry.get("appearances", [])
            )
        ),
        None,
    )
    if light_entry is None or dark_entry is None:
        raise ValueError(f"{asset_name}.colorset needs universal light and dark entries")

    return {
        "dark": color_components_to_hex(dark_entry),
        "light": color_components_to_hex(light_entry),
    }


def color_components_to_hex(entry: dict[str, object]) -> int:
    color = entry.get("color")
    if not isinstance(color, dict) or color.get("color-space") != "srgb":
        raise ValueError("color entry must use sRGB components")
    components = color.get("components")
    if not isinstance(components, dict):
        raise ValueError("color entry has no component map")
    try:
        values = [round(float(components[channel]) * 255) for channel in ("red", "green", "blue")]
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError(f"invalid RGB components: {error}") from error
    if any(value < 0 or value > 255 for value in values):
        raise ValueError("RGB components must be between 0 and 1")
    return values[0] << 16 | values[1] << 8 | values[2]


def relative_luminance(hex_value: int) -> float:
    """WCAG relative luminance."""
    channels = [
        ((hex_value >> 16) & 0xFF) / 255,
        ((hex_value >> 8) & 0xFF) / 255,
        (hex_value & 0xFF) / 255,
    ]
    linear = [
        c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
        for c in channels
    ]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast_ratio(a: int, b: int) -> float:
    la, lb = relative_luminance(a), relative_luminance(b)
    lighter, darker = max(la, lb), min(la, lb)
    return (lighter + 0.05) / (darker + 0.05)


# Every pair the UI actually renders. Each entry:
#   (foreground token, background token, minimum ratio, what it is)
#
# Deliberately not "every token against every other" — that would flag pairs
# nothing draws, and a checker that cries wolf gets muted.
PAIRS: list[tuple[str, str, float, str]] = [
    # Body and heading text on each surface.
    ("textPrimary", "backgroundPrimary", AA_NORMAL, "Primary text on the app background"),
    ("textPrimary", "backgroundSecondary", AA_NORMAL, "Primary text on the secondary background"),
    ("textPrimary", "surfaceElevated", AA_NORMAL, "Primary text on a card"),
    ("textSecondary", "backgroundPrimary", AA_NORMAL, "Secondary text on the app background"),
    ("textSecondary", "surfaceElevated", AA_NORMAL, "Secondary text on a card"),

    # textMuted is captions and metadata — still text, still AA.
    ("textMuted", "backgroundPrimary", AA_NORMAL, "Muted text on the app background"),
    ("textMuted", "surfaceElevated", AA_NORMAL, "Muted text on a card"),

    # The accessible champagne exists precisely so gold TEXT clears AA.
    ("accentChampagneAccessible", "backgroundPrimary", AA_NORMAL, "Accent text on the app background"),
    ("accentChampagneAccessible", "surfaceElevated", AA_NORMAL, "Accent text on a card"),

    # Plain champagne is for fills, borders, and icons — non-text UI, so the
    # 3:1 component floor applies rather than 4.5:1. It must NOT be used for
    # text in light mode; that is what the accessible variant is for.
    ("accentChampagne", "backgroundPrimary", AA_LARGE, "Accent fill/icon on the app background"),
    ("accentChampagne", "surfaceElevated", AA_LARGE, "Accent fill/icon on a card"),

    # Status colours. Spec §19 forbids colour-only meaning, so these always
    # accompany a word or icon — the 3:1 non-text floor is the right bar.
    ("successOlive", "backgroundPrimary", AA_LARGE, "Success indicator"),
    ("warningAmber", "backgroundPrimary", AA_LARGE, "Warning indicator"),
    ("destructive", "backgroundPrimary", AA_LARGE, "Destructive indicator"),

    # Text ON the champagne fill — primary buttons. `AstraPrimaryButtonStyle`
    # uses `textOnAccent` (a fixed near-black ink), NOT backgroundPrimary; an
    # earlier draft of this list guessed wrong and invented a failure that no
    # screen renders. Verified against the button's own implementation.
    ("textOnAccent", "accentChampagne", AA_NORMAL, "Button label on a champagne fill"),
    ("textOnAccent", "accentChampagnePressed", AA_NORMAL, "Button label on a pressed champagne fill"),
]

# Pairs that are known-failing and deliberately allowed, each with a reason and
# the constraint that keeps it safe. An exemption without a stated guard is how
# a checker becomes decorative.
EXEMPTIONS: dict[tuple[str, str, str], str] = {
    ("divider", "backgroundPrimary", "dark"):
        "Dividers are decorative hairlines, not information. Spec §3 calls for "
        "'subtle 1px borders in dark mode' — visible contrast here would be a "
        "design regression, and nothing is conveyed by the divider alone.",
    ("divider", "backgroundPrimary", "light"):
        "Same as dark: decorative separator, carries no meaning.",
}


def main() -> int:
    if not COLOR_FILE.exists():
        print(f"FAIL: cannot find {COLOR_FILE.relative_to(REPO)}")
        return 1

    tokens = parse_tokens(COLOR_FILE.read_text())
    if not tokens:
        # A silent zero-token parse would make this script pass forever while
        # checking nothing — the worst possible failure mode for a guard.
        print("FAIL: parsed 0 tokens. AstraColor.swift's shape probably changed;")
        print("      fix parse_tokens() rather than deleting this check.")
        return 1

    failures: list[str] = []
    checked = 0

    for fg, bg, minimum, label in PAIRS:
        for scheme in ("dark", "light"):
            if fg not in tokens:
                failures.append(f"unknown token '{fg}' in pair list — was it renamed?")
                continue
            if bg not in tokens:
                failures.append(f"unknown token '{bg}' in pair list — was it renamed?")
                continue
            if (fg, bg, scheme) in EXEMPTIONS:
                continue

            ratio = contrast_ratio(tokens[fg][scheme], tokens[bg][scheme])
            checked += 1
            if ratio < minimum:
                failures.append(
                    f"{scheme:5} {label}\n"
                    f"          {fg} on {bg} = {ratio:.2f}:1, needs {minimum}:1\n"
                    f"          (#{tokens[fg][scheme]:06X} on #{tokens[bg][scheme]:06X})"
                )

    print(f"Parsed {len(tokens)} colour tokens; checked {checked} pairs "
          f"across both appearances.")

    if failures:
        print(f"\nCONTRAST CHECK FAILED: {len(failures)} problem(s)\n")
        for failure in failures:
            print(f"  - {failure}")
        print(
            "\nFix by changing the token, or by using a different token at the "
            "call site\n(accentChampagneAccessible exists for exactly this "
            "reason). Adding an\nexemption is a last resort and needs a written "
            "justification."
        )
        return 1

    print("All checked pairs meet their WCAG minimum.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
