#!/usr/bin/env python3
"""
check_schema_drift.py — fail when a Swift domain enum and its corresponding
Postgres enum type have drifted apart.

Why this exists
----------------
`ios/AstraStyle/Domain/Models/Enums.swift` documents its own invariant:

    Every raw value below is a member of the corresponding Postgres enum
    defined in supabase/migrations/20260728100100_core_enums.sql. [...] a
    mismatch does not fail at compile time, it fails at INSERT time with
    "invalid input value for enum", which is a slow and confusing way to
    find a typo.

Five such mismatches were found and fixed by hand while building the
vertical slice (see `git log` on this file / on Enums.swift). Hand-auditing
does not scale and does not run in CI. This script parses both sides and
diffs them mechanically, so the next drift fails a `deno`-speed check
instead of an `INSERT`.

What it checks
---------------
For every Swift `enum ...: String` in Enums.swift, this script either:
  (a) knows which Postgres `create type ... as enum (...)` it corresponds
      to (see ENUM_MAPPING below), and diffs the two value sets exactly, or
  (b) is explicitly declared to have no Postgres counterpart at all (see
      NO_DB_COUNTERPART below), because the column it backs is `text`,
      `jsonb`, a `smallint` score, or (for `KyraIntent`) not a persisted
      column at all — and is skipped, or
  (c) is neither mapped nor declared exempt, which is treated as a hard
      error: every enum must be explicitly classified so a newly added,
      never-categorized enum can't silently slip past this check.

Name-based auto-matching (e.g. lowercasing `ClothingCategory` to
`clothing_category`) was deliberately NOT used as the primary mechanism:
several real, intentional pairs don't convert mechanically (`ItemCondition`
-> `condition`, not `item_condition`; `ItemFit` -> `fit_preference`), and a
naive auto-matcher would have silently skipped exactly the kind of pair
that produced two of the five bugs already found (ItemCondition,
ClosetImageType). An explicit table is more code but is actually correct.

Usage
-----
    python3 scripts/check_schema_drift.py
    python3 scripts/check_schema_drift.py --swift-file path/to/Enums.swift \
        --sql-file path/to/core_enums.sql

Exit code 0 = no drift found. Exit code 1 = drift found, or an
unclassified Swift enum was encountered (see "what it checks" (c) above).
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SWIFT_FILE = REPO_ROOT / "ios/AstraStyle/Domain/Models/Enums.swift"
DEFAULT_SQL_FILE = REPO_ROOT / "supabase/migrations/20260728100100_core_enums.sql"

# Enums that legitimately live outside the two files above.
#
# Originally this script read exactly one Swift file and one migration, which
# was true when it was written and quietly stopped being true the moment a
# feature declared its enums next to its model instead of in the shared file.
# A drift checker that silently covers less than it appears to is worse than
# none: it reports "OK: every mapped Swift enum matches" while the pair that
# actually drifted was never in scope. These lists are the fix, and the
# coverage assertion at the end of main() is the guard that keeps them honest.
EXTRA_SWIFT_FILES = [
    REPO_ROOT / "ios/AstraStyle/Domain/Models/FrameProfile.swift",
    # The §6.9 preference vector. Neither of its enums has a Postgres enum type
    # behind it (the whole vector is one jsonb column), but they are String-backed
    # and persisted -- the raw values ARE the jsonb keys and the stored confidence
    # strings. Listing the file means a rename here has to be classified below
    # rather than sailing past a checker that never opened the file.
    REPO_ROOT / "ios/AstraStyle/Domain/Models/StylePreferenceVector.swift",
]
EXTRA_SQL_FILES = [
    REPO_ROOT / "supabase/migrations/20260729120000_frame_profile.sql",
]

# ============================================================================
# The explicit classification table.
#
# Swift enum name -> Postgres enum type name it must match exactly.
#
# Every entry here was verified by reading both the Swift enum and the
# Postgres column(s) that declare that type, not guessed from naming alone.
# ============================================================================
ENUM_MAPPING: dict[str, str] = {
    "ClothingCategory": "clothing_category",
    "LaundryState": "laundry_state",
    "KyraVerdict": "kyra_verdict",
    "AvailabilityState": "availability_state",
    "ItemCondition": "condition",
    "ItemFit": "fit_preference",
    # Frame-aware fit (docs/14-frame-fit.md). Declared in FrameProfile.swift and
    # 20260729120000_frame_profile.sql -- both reached via the EXTRA_* tables above.
    "FrameTaper": "frame_taper",
    "FrameProportion": "frame_proportion",
    "FrameScale": "frame_scale",
    "ClosetImageType": "image_type",
    "OutfitSource": "outfit_source",
    "StyleFeedbackTargetType": "feedback_target_type",
    "StyleFeedbackSignal": "feedback_signal",
    "OccasionSource": "occasion_source",
    "KyraMessageRole": "kyra_message_role",
    "StyleMemoryType": "memory_type",
    "StudioGenerationStatus": "generation_status",
    "SubscriptionStatus": "subscription_status",
    "SubscriptionEnvironment": "subscription_environment",
    "SubscriptionTier": "subscription_tier",
    "UnitsPreference": "units_preference",
    "ThemePreference": "theme_preference",
    "StyleIdentity": "style_identity",
    "FormalityLevel": "formality_preference",
    "AccessoryPreference": "accessory_preference",
    "DressCode": "dress_code",
    # `outfit_items.role` deliberately reuses the `clothing_category` type
    # rather than declaring its own (see the column comment in
    # supabase/migrations/20260728100400_outfits.sql: "Reuses clothing_category
    # rather than a separate enum"). OutfitItemRole is documented in Swift as
    # "A superset of ClothingCategory to allow layering pieces" — but the
    # column it is actually inserted into cannot legally hold anything outside
    # clothing_category's value set, so `layering_piece` is checked against
    # clothing_category here, not exempted.
    "OutfitItemRole": "clothing_category",
}

# Swift enums intentionally NOT backed by a same-shaped Postgres enum column,
# with the reason recorded next to each so a future reader doesn't have to
# re-derive it. Adding an enum here is a deliberate exemption, not a default.
NO_DB_COUNTERPART: dict[str, str] = {
    "GarmentPattern": "closet_items.pattern is `text`, not an enum column.",
    "StyleGoal": (
        "style_profiles.style_goals is `jsonb` (array of goal tags), not an enum column. "
        "Kept free-text server-side on purpose so a user-typed goal can be stored later; "
        "the closed §6.4 list exists only to drive the onboarding UI."
    ),
    "Season": "closet_items.seasonality is `jsonb` (array of season tags), not an enum column.",
    "KyraIntent": "the `intent` field of Kyra's JSON response schema (spec §11) — never a persisted column.",
    "ToleranceLevel": "logo_tolerance/trend_tolerance are `smallint` 0-100 scores, not enum columns.",
    "FitIssue": "body_profiles.fit_notes is `jsonb` (open-ended list per spec §6.6), not an enum column.",
    "OccupationCategory": "lifestyle_profiles.occupation_category is `text`, not an enum column.",
    "StyleDimension": (
        "keys inside the style_profiles.preference_vector jsonb document (§6.9's eight axes), "
        "not an enum column -- so Postgres does not constrain the value set and a Swift-side "
        "rename is a silent data-format change, not an INSERT error. Changing a raw value here "
        "requires a StylePreferenceVector.currentVersion bump and a backfill."
    ),
    "PreferenceConfidence": (
        "the `confidence` field inside each dimension of the style_profiles.preference_vector "
        "jsonb document, not an enum column."
    ),
    "LaundryCadence": (
        "lifestyle_profiles.laundry_cadence is `text` by explicit migration comment "
        "(\"cadence phrasing ... is naturally free-form input rather than a small closed set\")."
    ),
}


@dataclass
class SwiftEnum:
    name: str
    # ordered list of (case_identifier, raw_value)
    cases: list[tuple[str, str]] = field(default_factory=list)

    @property
    def raw_values(self) -> set[str]:
        return {raw for _, raw in self.cases}


@dataclass
class PgEnum:
    name: str
    members: list[str] = field(default_factory=list)

    @property
    def value_set(self) -> set[str]:
        return set(self.members)


def _strip_swift_comments(text: str) -> str:
    """Remove `//` line comments and `/* */` block comments, preserving
    line structure (so later line-based scanning stays simple), and without
    touching the contents of string literals (raw values are always plain
    ASCII with no embedded `//` or `/*` in this file, so a straightforward
    scan is sufficient — this is not a general Swift parser)."""
    out = []
    i = 0
    n = len(text)
    in_string = False
    while i < n:
        ch = text[i]
        if in_string:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if ch == '"':
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
            out.append(ch)
            i += 1
            continue
        if text[i : i + 2] == "//":
            # skip to end of line, keep the newline
            j = text.find("\n", i)
            if j == -1:
                break
            i = j
            continue
        if text[i : i + 2] == "/*":
            j = text.find("*/", i + 2)
            if j == -1:
                break
            # preserve newlines inside the block comment so line numbers
            # (not currently used, but kept honest) don't drift
            out.append("\n" * text.count("\n", i, j + 2))
            i = j + 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def _find_matching_brace(text: str, open_brace_index: int) -> int:
    """Given the index of a `{`, return the index of its matching `}`,
    accounting for nested braces. Assumes comments/strings were already
    stripped/neutralized by the caller for brace-counting purposes (string
    literals here never contain braces, so no special-casing is needed)."""
    depth = 0
    i = open_brace_index
    n = len(text)
    while i < n:
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError(f"Unbalanced braces starting at index {open_brace_index}")


ENUM_DECL_RE = re.compile(r"public\s+enum\s+(\w+)\s*:\s*String\b[^\{]*\{")
# A genuine case declaration, e.g. `case top` or `case wornOnce = "worn_once"`.
# Deliberately excludes switch pattern-matches like `case .top:`, which always
# have a leading `.` immediately after `case` — a declaration never does.
CASE_LINE_RE = re.compile(r"^\s*case\s+(?!\.)(.+)$")
CASE_SPEC_RE = re.compile(r'^\s*([A-Za-z_]\w*)\s*(?:=\s*"([^"]*)")?\s*$')


def parse_swift_enums(text: str) -> list[SwiftEnum]:
    clean = _strip_swift_comments(text)
    enums: list[SwiftEnum] = []
    for m in ENUM_DECL_RE.finditer(clean):
        name = m.group(1)
        open_brace = clean.index("{", m.start())
        close_brace = _find_matching_brace(clean, open_brace)
        body = clean[open_brace + 1 : close_brace]

        swift_enum = SwiftEnum(name=name)
        for line in body.splitlines():
            case_match = CASE_LINE_RE.match(line)
            if not case_match:
                continue
            rest = case_match.group(1)
            # Support `case a, b = "b_raw", c` on one line.
            for spec in rest.split(","):
                spec = spec.strip()
                if not spec:
                    continue
                spec_match = CASE_SPEC_RE.match(spec)
                if not spec_match:
                    # Not a simple case declaration (e.g. an associated-value
                    # case) — this file doesn't use those, so treat as a hard
                    # parse error rather than silently dropping data.
                    raise ValueError(
                        f"Could not parse case spec {spec!r} in enum {name} "
                        f"(line: {line!r})"
                    )
                identifier, raw = spec_match.group(1), spec_match.group(2)
                raw_value = raw if raw is not None else identifier
                swift_enum.cases.append((identifier, raw_value))
        enums.append(swift_enum)
    return enums


PG_TYPE_RE = re.compile(
    r"create\s+type\s+(\w+)\s+as\s+enum\s*\((.*?)\)\s*;", re.DOTALL | re.IGNORECASE
)
PG_MEMBER_RE = re.compile(r"'((?:[^'\\]|\\.)*)'")


def parse_pg_enums(text: str) -> list[PgEnum]:
    enums = []
    for m in PG_TYPE_RE.finditer(text):
        name = m.group(1)
        body = m.group(2)
        members = [mm.group(1) for mm in PG_MEMBER_RE.finditer(body)]
        enums.append(PgEnum(name=name, members=members))
    return enums


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--swift-file", type=Path, default=DEFAULT_SWIFT_FILE)
    parser.add_argument("--sql-file", type=Path, default=DEFAULT_SQL_FILE)
    args = parser.parse_args()

    if not args.swift_file.is_file():
        print(f"error: Swift file not found: {args.swift_file}", file=sys.stderr)
        return 2
    if not args.sql_file.is_file():
        print(f"error: SQL file not found: {args.sql_file}", file=sys.stderr)
        return 2

    def read_all(primary: Path, extras: list[Path], label: str) -> str:
        chunks = [primary.read_text(encoding="utf-8")]
        for extra in extras:
            if not extra.is_file():
                print(
                    f"error: {label} file listed in the EXTRA_* table is missing: {extra}\n"
                    f"       Remove the entry or restore the file -- a silently skipped\n"
                    f"       source is how this checker starts passing vacuously.",
                    file=sys.stderr,
                )
                raise SystemExit(2)
            chunks.append(extra.read_text(encoding="utf-8"))
        return "\n".join(chunks)

    swift_text = read_all(args.swift_file, EXTRA_SWIFT_FILES, "Swift")
    sql_text = read_all(args.sql_file, EXTRA_SQL_FILES, "SQL")

    swift_enums = {e.name: e for e in parse_swift_enums(swift_text)}
    pg_enums = {e.name: e for e in parse_pg_enums(sql_text)}

    if not swift_enums:
        print(f"error: parsed zero Swift enums out of {args.swift_file} — parser is broken.", file=sys.stderr)
        return 2
    if not pg_enums:
        print(f"error: parsed zero Postgres enum types out of {args.sql_file} — parser is broken.", file=sys.stderr)
        return 2

    errors: list[str] = []
    checked_pairs = 0

    # 1. Every Swift enum must be classified: mapped, exempt, or an error.
    for name, swift_enum in sorted(swift_enums.items()):
        if name in NO_DB_COUNTERPART:
            continue
        if name not in ENUM_MAPPING:
            errors.append(
                f"UNCLASSIFIED SWIFT ENUM: `{name}` (in {args.swift_file.name}) is neither in "
                f"ENUM_MAPPING nor NO_DB_COUNTERPART in {Path(__file__).name}. Classify it: "
                f"add it to ENUM_MAPPING with the Postgres enum type it must match, or to "
                f"NO_DB_COUNTERPART with a one-line reason it has none."
            )
            continue

        pg_type_name = ENUM_MAPPING[name]
        pg_enum = pg_enums.get(pg_type_name)
        if pg_enum is None:
            errors.append(
                f"MISSING POSTGRES TYPE: Swift enum `{name}` is mapped to Postgres type "
                f"`{pg_type_name}` in ENUM_MAPPING, but no `create type {pg_type_name} as enum (...)` "
                f"was found in {args.sql_file.name}. Either the mapping is stale or the migration "
                f"was renamed/removed."
            )
            continue

        checked_pairs += 1
        swift_only = swift_enum.raw_values - pg_enum.value_set
        pg_only = pg_enum.value_set - swift_enum.raw_values

        for value in sorted(swift_only):
            case_ids = [c for c, r in swift_enum.cases if r == value]
            case_id = case_ids[0] if case_ids else "?"
            errors.append(
                f"DRIFT: {name}.{case_id} has raw value \"{value}\", which is NOT a member of "
                f"Postgres enum `{pg_type_name}` ({args.sql_file.name}). An INSERT/UPDATE writing "
                f"this value will fail with 'invalid input value for enum {pg_type_name}'."
            )
        for value in sorted(pg_only):
            errors.append(
                f"DRIFT: Postgres enum `{pg_type_name}` has member \"{value}\" with no corresponding "
                f"case in Swift enum `{name}` ({args.swift_file.name}). The client can never "
                f"construct/decode this value even though the database allows it."
            )

    # 2. Flag (non-fatally) any Postgres enum type nobody maps to at all —
    # not necessarily a bug (a type might legitimately have no Swift mirror
    # yet), but worth a human's attention since it's a coverage gap in this
    # very check.
    mapped_pg_types = set(ENUM_MAPPING.values())
    unmapped_pg_types = sorted(set(pg_enums) - mapped_pg_types)

    # 3. Every mapping target and every exemption should refer to an enum
    # that actually still exists in Enums.swift — catches stale entries in
    # this script itself after a rename/removal.
    for name in ENUM_MAPPING:
        if name not in swift_enums:
            errors.append(
                f"STALE MAPPING: ENUM_MAPPING references Swift enum `{name}`, which no longer "
                f"exists in {args.swift_file.name}. Remove the stale entry from {Path(__file__).name}."
            )
    for name in NO_DB_COUNTERPART:
        if name not in swift_enums:
            errors.append(
                f"STALE EXEMPTION: NO_DB_COUNTERPART references Swift enum `{name}`, which no longer "
                f"exists in {args.swift_file.name}. Remove the stale entry from {Path(__file__).name}."
            )

    def _display_path(p: Path) -> Path:
        try:
            return p.relative_to(REPO_ROOT)
        except ValueError:
            return p

    print(f"Parsed {len(swift_enums)} Swift enum(s) from {_display_path(args.swift_file)}")
    print(f"Parsed {len(pg_enums)} Postgres enum type(s) from {_display_path(args.sql_file)}")
    print(f"Checked {checked_pairs} mapped pair(s); {len(NO_DB_COUNTERPART)} Swift enum(s) exempted (no DB counterpart).")
    if unmapped_pg_types:
        print(
            "NOTE (not a failure): Postgres enum type(s) with no Swift mapping in ENUM_MAPPING: "
            + ", ".join(unmapped_pg_types)
        )
    print()

    if errors:
        print(f"SCHEMA DRIFT: {len(errors)} problem(s) found:\n", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        print(file=sys.stderr)
        return 1

    print("OK: every mapped Swift enum matches its Postgres enum exactly.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
