#!/usr/bin/env python3
# =============================================================================
# scripts/check_progress.py — keep docs/03-progress.md honest.
# =============================================================================
# A hand-maintained status document is accurate the day it is written and
# quietly wrong a week later. That is worse than having none, because people
# trust it: the whole value of 03-progress.md is that someone can read it
# instead of spending an hour re-deriving the state of the repo from git log,
# file counts, a test run and live HTTP probes. A status file that has drifted
# costs that hour AND sends them down a wrong path first.
#
# So this checker enforces the parts of that document a script can actually
# settle. It deliberately does NOT try to decide whether a ticket is "really"
# done — that judgement needs a human reading acceptance criteria against code,
# and a checker that pretended otherwise would either block honest work or,
# worse, rubber-stamp it. What it can do is make the document structurally
# incapable of the failure modes that actually happen in practice:
#
#   1. A ticket is added to 02-task-breakdown.md and never appears here.
#   2. A ticket is renamed or removed and its stale row lingers here.
#   3. The summary table's counts stop matching the rows beneath them, usually
#      because someone flipped a status and didn't re-add the column.
#   4. A row cites a file or test as evidence that no longer exists — the most
#      insidious one, because the row still *reads* as substantiated.
#   5. A row claims an Edge Function is deployed when the endpoint-mapping test
#      says otherwise.
#
# Every one of those is a real drift mode with a cheap mechanical answer. The
# expensive judgement is left where it belongs.
#
# Exit code 0 = consistent. 1 = drift, with every problem listed at once rather
# than one per run, so a single fix pass can clear them all.
# =============================================================================

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TASKS = REPO_ROOT / "docs" / "02-task-breakdown.md"
PROGRESS = REPO_ROOT / "docs" / "03-progress.md"
ENDPOINT_TEST = (
    REPO_ROOT / "ios" / "AstraStyle" / "Tests" / "UnitTests" / "EndpointDeploymentMappingTests.swift"
)
FUNCTIONS_DIR = REPO_ROOT / "supabase" / "functions"

VALID_STATUSES = {"Done", "Partial", "Not started", "Unverifiable"}

# Ticket ids look like `P2-ONBOARD-07`. In 02-task-breakdown.md they head a
# section as `#### \`P2-ONBOARD-07\` — title`; in 03-progress.md they open a
# table row as `| P2-ONBOARD-07 | Done | … |`.
TICKET_RE = re.compile(r"\bP[1-7]-[A-Z]+-\d{2}\b")
TASK_HEADING_RE = re.compile(r"^####\s+`(P[1-7]-[A-Z]+-\d{2})`")
PROGRESS_ROW_RE = re.compile(r"^\|\s*(P[1-7]-[A-Z]+-\d{2})\s*\|\s*([^|]+?)\s*\|(.*)\|\s*$")

# Evidence citations worth resolving. Paths are cited bare or in backticks and
# may carry a :line or :line-line suffix, which we strip before checking. We
# only check paths that look like real repo paths — a prose mention of
# "Features/Closet/" with no file is not a citation, and treating it as one
# would make the checker nag about its own examples.
PATH_RE = re.compile(
    r"`([A-Za-z0-9_./-]+\.(?:swift|ts|sql|py|sh|yml|yaml|json|md|xcconfig))(?::\d+(?:-\d+)?)?`"
)

# Summary table rows: | 1 — Foundation | 25 | 12 | 13 | 0 |
SUMMARY_ROW_RE = re.compile(
    r"^\|\s*(\d)\s*—[^|]*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*$"
)
TOTAL_ROW_RE = re.compile(
    r"^\|\s*\*\*Total\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|\s*$"
)

problems: list[str] = []


def fail(message: str) -> None:
    problems.append(message)


def read(path: Path) -> str:
    if not path.exists():
        fail(f"Missing required file: {path.relative_to(REPO_ROOT)}")
        return ""
    return path.read_text(encoding="utf-8")


def main() -> int:
    tasks_text = read(TASKS)
    progress_text = read(PROGRESS)
    if not tasks_text or not progress_text:
        report()
        return 1

    # --- 1. Every ticket appears exactly once, and no invented ids ----------
    #
    # Order matters less than coverage here: the roadmap reorders work all the
    # time, but a ticket that exists and is untracked is invisible work.
    declared = [m.group(1) for m in map(TASK_HEADING_RE.match, tasks_text.splitlines()) if m]
    declared_set = set(declared)
    if len(declared) != len(declared_set):
        dupes = sorted({t for t in declared if declared.count(t) > 1})
        fail(f"02-task-breakdown.md declares duplicate ticket ids: {', '.join(dupes)}")

    rows: dict[str, tuple[str, str]] = {}
    row_order: list[str] = []
    for line in progress_text.splitlines():
        m = PROGRESS_ROW_RE.match(line)
        if not m:
            continue
        ticket, status, evidence = m.group(1), m.group(2).strip(), m.group(3)
        if ticket in rows:
            fail(f"03-progress.md has more than one row for {ticket}")
        rows[ticket] = (status, evidence)
        row_order.append(ticket)

    missing = sorted(declared_set - set(rows))
    if missing:
        fail(
            f"{len(missing)} ticket(s) in 02-task-breakdown.md have no row in 03-progress.md: "
            + ", ".join(missing)
        )

    unknown = sorted(set(rows) - declared_set)
    if unknown:
        fail(
            f"{len(unknown)} row(s) in 03-progress.md reference tickets that no longer exist "
            f"in 02-task-breakdown.md: " + ", ".join(unknown)
        )

    # --- 2. Statuses come from the documented vocabulary --------------------
    #
    # Left open-ended, this drifts into "Mostly done", "In progress", "Blocked?"
    # and the summary counts stop meaning anything.
    for ticket, (status, _) in sorted(rows.items()):
        if status not in VALID_STATUSES:
            fail(
                f"{ticket} has status {status!r}, which is not one of: "
                + ", ".join(sorted(VALID_STATUSES))
            )

    # --- 3. Summary counts match the rows -----------------------------------
    #
    # This is the check that fires most often in practice: someone flips one
    # ticket to Done and forgets the table at the top, which is precisely the
    # number everyone else reads.
    counted: dict[str, dict[str, int]] = {}
    for ticket, (status, _) in rows.items():
        phase = ticket[1]
        counted.setdefault(phase, {s: 0 for s in VALID_STATUSES})
        if status in VALID_STATUSES:
            counted[phase][status] += 1

    claimed_totals = [0, 0, 0, 0]
    for line in progress_text.splitlines():
        m = SUMMARY_ROW_RE.match(line)
        if not m:
            continue
        phase, total, done, partial, not_started = m.group(1), *(int(g) for g in m.groups()[1:])
        actual = counted.get(phase)
        if actual is None:
            fail(f"Summary table claims a Phase {phase} row, but no Phase {phase} tickets exist")
            continue
        actual_total = sum(actual.values())
        for label, claim, real in (
            ("total", total, actual_total),
            ("Done", done, actual["Done"]),
            ("Partial", partial, actual["Partial"]),
            ("Not started", not_started, actual["Not started"]),
        ):
            if claim != real:
                fail(
                    f"Summary table says Phase {phase} has {claim} {label}, "
                    f"but the ticket rows show {real}"
                )
        claimed_totals = [a + b for a, b in zip(claimed_totals, (total, done, partial, not_started))]

    for line in progress_text.splitlines():
        m = TOTAL_ROW_RE.match(line)
        if not m:
            continue
        claimed = [int(g) for g in m.groups()]
        if claimed != claimed_totals:
            fail(
                f"Summary Total row is {claimed}, but the per-phase rows sum to {claimed_totals} "
                "(total, Done, Partial, Not started)"
            )
        if claimed[0] != len(declared_set):
            fail(
                f"Summary Total claims {claimed[0]} tickets, but 02-task-breakdown.md declares "
                f"{len(declared_set)}"
            )

    # --- 4. Cited evidence resolves, for rows that claim something exists ---
    #
    # The point of requiring evidence is that a status can be checked. A row
    # citing a file that was renamed or deleted still READS as substantiated,
    # which makes this the most valuable check here and the one most likely to
    # catch a real regression rather than a bookkeeping slip.
    #
    # But it applies ONLY to `Done` rows, and that restriction is the whole
    # design, not a shortcut. A `Partial` or `Not started` row earns its status
    # precisely BY citing things that are absent — "no `Staging.xcconfig`",
    # "queries a `wardrobe_scores` table that no migration creates". Demanding
    # those resolve would fail the most informative rows in the document and
    # teach the author to write vaguer evidence to keep CI quiet, which is the
    # exact opposite of what this file is for. A `Done` row makes an
    # unqualified claim, so everything it cites must be real.
    #
    # Paths are resolved by suffix rather than from the repo root, because
    # citations should be as short as they can be while staying unambiguous
    # (`App/AppContainer.swift`, not the full ios/AstraStyle/... prefix on
    # every one of 178 rows). An ambiguous suffix still resolves — this is an
    # existence check, not a uniqueness check.
    for ticket in row_order:
        status, evidence = rows[ticket]
        if status != "Done":
            continue
        for path_str in PATH_RE.findall(evidence):
            candidate = REPO_ROOT / path_str
            if candidate.exists():
                continue
            # Suffix match: `App/AppContainer.swift` should find
            # ios/AstraStyle/App/AppContainer.swift.
            name = path_str.rsplit("/", 1)[-1]
            if any(str(p).endswith("/" + path_str) for p in REPO_ROOT.rglob(name)):
                continue
            fail(
                f"{ticket} is marked Done but cites `{path_str}`, which does not exist. "
                "Either the evidence is stale or the status is."
            )

    # --- 5. Deployment claims match the endpoint-mapping test ---------------
    #
    # EndpointDeploymentMappingTests pins the set of slugs that must be live.
    # If a row here says a function is deployed and that test disagrees, one of
    # them is lying to a reader who has no reason to doubt either.
    endpoint_text = ENDPOINT_TEST.read_text(encoding="utf-8") if ENDPOINT_TEST.exists() else ""
    m = re.search(r"requiredNow[^=]*=\s*\[([^\]]*)\]", endpoint_text)
    if m:
        required_now = set(re.findall(r'"([^"]+)"', m.group(1)))
        on_disk = {
            d.name
            for d in FUNCTIONS_DIR.iterdir()
            if d.is_dir() and not d.name.startswith("_") and (d / "index.ts").exists()
        } if FUNCTIONS_DIR.exists() else set()
        missing_dirs = sorted(required_now - on_disk)
        if missing_dirs:
            fail(
                "EndpointDeploymentMappingTests requires slug(s) with no function directory: "
                + ", ".join(missing_dirs)
            )
    else:
        fail(
            "Could not read `requiredNow` out of EndpointDeploymentMappingTests.swift — "
            "the deployment cross-check is silently not running. Fix the pattern or the test."
        )

    # --- 6. The audit stamp is present --------------------------------------
    #
    # Not a date-freshness check: nagging about staleness on every run trains
    # people to ignore the checker. It only insists the stamp exists, so a
    # reader can judge for themselves how much to trust the document.
    if not re.search(r"\*\*Last audited:\*\*\s*\d{4}-\d{2}-\d{2}", progress_text):
        fail("03-progress.md is missing its `**Last audited:** YYYY-MM-DD` stamp")

    report()
    if problems:
        return 1

    done = sum(c["Done"] for c in counted.values())
    partial = sum(c["Partial"] for c in counted.values())
    not_started = sum(c["Not started"] for c in counted.values())
    unverifiable = sum(c["Unverifiable"] for c in counted.values())
    extra = f", {unverifiable} unverifiable" if unverifiable else ""
    print(
        f"Progress doc OK — {len(rows)} tickets tracked "
        f"({done} done, {partial} partial, {not_started} not started{extra})."
    )
    return 0


def report() -> None:
    if not problems:
        return
    print("docs/03-progress.md has drifted from the repo:\n", file=sys.stderr)
    for p in problems:
        print(f"  • {p}", file=sys.stderr)
    print(
        "\nUpdate the document to match reality (or fix the code it describes). "
        "Status changes belong in the same commit as the work they describe.",
        file=sys.stderr,
    )


if __name__ == "__main__":
    sys.exit(main())
