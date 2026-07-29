#!/usr/bin/env python3
"""Fail the build when a Swift model's coding keys don't match its Postgres table.

`check_schema_drift.py` compares Swift ENUM CASES against Postgres enum values.
This is the same idea one level up: Swift CODING KEYS against actual columns.

It exists because of a bug that had shipped and would have kept shipping.
`BodyProfile` declared coding keys `height_value`, `chest`, `waist`, `inseam`
and `neck`. The columns are `height_value_cm`, `chest_cm`, `waist_cm`,
`inseam_cm` and `neck_cm`. Nothing failed. Every property on that model is
Optional, so Swift's synthesised decoder calls `decodeIfPresent`, finds nothing
under the wrong key, and returns nil — silently, for every user, forever.

That failure mode is the dangerous one. It does not throw, it does not log, and
"every measurement is nil" is indistinguishable from the legitimate "I don't
know" answer that spec §6.6 explicitly supports. It was found only because a
feature finally tried to READ the measurements, months after they stopped being
saved correctly. A wrong key on a NON-optional property throws loudly on the
first decode and gets fixed in minutes; a wrong key on an optional one is
invisible until someone happens to look.

Run locally:  python3 scripts/check_column_drift.py
CI runs it on every PR (.github/workflows/ios.yml).
"""

from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
MODELS_DIR = REPO / "ios/AstraStyle/Domain/Models"
MIGRATIONS_DIR = REPO / "supabase/migrations"

# Swift model type -> Postgres table it maps to.
#
# Explicit rather than inferred from naming. A model that maps to no table (a
# view model, a request payload, a value type that lives only in memory) must
# NOT be silently skipped by a naming heuristic — it must be absent from here
# on purpose, so that adding a new persisted model and forgetting to register
# it is a visible omission rather than an invisible one.
MODEL_TABLES: dict[str, str] = {
    "Profile": "profiles",
    "BodyProfile": "body_profiles",
    "StyleProfile": "style_profiles",
    "LifestyleProfile": "lifestyle_profiles",
    "ClosetItem": "closet_items",
    "ClosetItemImage": "closet_item_images",
    "Outfit": "outfits",
    "OutfitItem": "outfit_items",
    "OutfitWear": "outfit_wears",
    "StyleFeedback": "style_feedback",
    "StyleMemory": "style_memories",
    "KyraThread": "kyra_threads",
    "KyraMessage": "kyra_messages",
    "StudioGeneration": "studio_generations",
    "Subscription": "subscriptions",
}

# Coding keys that legitimately have no column, with the reason.
#
# Every entry is a hole in the check, so each one states why it is safe. An
# unexplained exemption is how this kind of script quietly stops checking.
ALLOWED_EXTRA_KEYS: dict[tuple[str, str], str] = {
    ("FrameProfile", "muscularity_hint"):
        "Added by 20260729120000_frame_profile; parsed from the ALTER, not the CREATE.",
}


def parse_columns() -> dict[str, set[str]]:
    """Table -> column names, from `create table` plus every later `alter table`.

    Reading only `create table` would be wrong the moment a feature adds a
    column in its own migration — which is exactly what frame fit does. A
    checker that reads a stale definition reports drift that isn't there and
    trains people to ignore it.
    """
    tables: dict[str, set[str]] = {}

    create_re = re.compile(
        r"create table (?:if not exists )?(?:public\.)?(\w+)\s*\((.*?)\n\)\s*;",
        re.DOTALL | re.IGNORECASE,
    )
    alter_re = re.compile(
        r"alter table (?:only )?(?:public\.)?(\w+)(.*?);",
        re.DOTALL | re.IGNORECASE,
    )
    add_col_re = re.compile(r"add column (?:if not exists )?(\w+)", re.IGNORECASE)
    drop_col_re = re.compile(r"drop column (?:if exists )?(\w+)", re.IGNORECASE)
    rename_col_re = re.compile(
        r"rename column (\w+) to (\w+)", re.IGNORECASE
    )

    for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
        sql = path.read_text()
        # Strip line comments so a column name mentioned in prose isn't parsed.
        sql = re.sub(r"--[^\n]*", "", sql)

        for table, body in create_re.findall(sql):
            columns = tables.setdefault(table, set())
            for line in body.split("\n"):
                line = line.strip()
                if not line or line.startswith(")"):
                    continue
                # Skip table-level constraints, which are not columns.
                first = line.split()[0].lower()
                if first in {
                    "primary", "unique", "foreign", "check", "constraint", "exclude",
                }:
                    continue
                name = line.split()[0].strip(",")
                if re.fullmatch(r"\w+", name):
                    columns.add(name)

        for table, body in alter_re.findall(sql):
            columns = tables.setdefault(table, set())
            columns.update(add_col_re.findall(body))
            for old, new in rename_col_re.findall(body):
                columns.discard(old)
                columns.add(new)
            for dropped in drop_col_re.findall(body):
                columns.discard(dropped)

    return tables


def parse_coding_keys() -> dict[str, set[str]]:
    """Swift type -> the string values of its `CodingKeys`.

    Handles both `case foo = "foo_bar"` and the bare `case foo`, where the key
    is the case name itself.
    """
    result: dict[str, set[str]] = {}

    for path in MODELS_DIR.rglob("*.swift"):
        source = path.read_text()
        # The enclosing type name is the last `struct X` before the CodingKeys.
        for match in re.finditer(
            r"(?:struct|final class|class)\s+(\w+)[^\n]*\{(.*?)\n\}",
            source,
            re.DOTALL,
        ):
            type_name, body = match.group(1), match.group(2)
            keys_match = re.search(
                r"enum CodingKeys\s*:[^\{]*\{(.*?)\n\s*\}", body, re.DOTALL
            )
            if not keys_match:
                continue
            keys: set[str] = set()
            for line in keys_match.group(1).split("\n"):
                line = line.strip()
                if not line.startswith("case "):
                    continue
                # `case a, b, c` and `case a = "x"` are both legal.
                for part in line[len("case "):].split(","):
                    part = part.strip()
                    if "=" in part:
                        raw = part.split("=", 1)[1].strip().strip('"')
                        keys.add(raw)
                    elif re.fullmatch(r"\w+", part):
                        keys.add(part)
            if keys:
                result[type_name] = keys

    return result


def main() -> int:
    tables = parse_columns()
    models = parse_coding_keys()

    if not tables:
        print("FAIL: parsed 0 tables out of supabase/migrations — parser is broken.")
        print("      Fix parse_columns() rather than deleting this check; a")
        print("      zero-table parse makes this script pass forever.")
        return 1
    if not models:
        print("FAIL: parsed 0 Swift models with CodingKeys — parser is broken.")
        return 1

    problems: list[str] = []
    checked = 0

    for model, table in sorted(MODEL_TABLES.items()):
        if model not in models:
            problems.append(
                f"{model}: registered against `{table}` but has no CodingKeys "
                f"block. Either it is not persisted (remove it from "
                f"MODEL_TABLES) or its keys are implicit (add them explicitly — "
                f"implicit camelCase keys never match snake_case columns)."
            )
            continue
        if table not in tables:
            problems.append(
                f"{model}: registered against table `{table}`, which no "
                f"migration creates. Renamed, or a typo here?"
            )
            continue

        checked += 1
        for key in sorted(models[model]):
            if key in tables[table]:
                continue
            if (model, key) in ALLOWED_EXTRA_KEYS:
                continue
            near = _closest(key, tables[table])
            hint = f" Did you mean `{near}`?" if near else ""
            problems.append(
                f"{model}: coding key \"{key}\" has no column on `{table}`.{hint}\n"
                f"      If the property is Optional this does NOT throw — it "
                f"decodes as nil forever, silently."
            )

    print(
        f"Parsed {len(tables)} tables and {len(models)} Swift models; "
        f"checked {checked} model/table pairs."
    )

    if problems:
        print(f"\nCOLUMN DRIFT: {len(problems)} problem(s)\n")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print("Every registered model's coding keys exist as columns.")
    return 0


def _closest(key: str, columns: set[str]) -> str | None:
    """A cheap 'did you mean' — prefix/suffix containment, no edit distance."""
    for column in sorted(columns):
        if column.startswith(key) or key.startswith(column):
            return column
    return None


if __name__ == "__main__":
    sys.exit(main())
