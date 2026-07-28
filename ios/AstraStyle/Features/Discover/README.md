# Discover

Owns editorial/educational content: the Discover tab (spec §6.21).

## What this module owns

- Kyra-curated lookbooks, style education, seasonal guides, fit guides, and brand spotlights.
- Explicitly **not** a generic shopping feed (spec §6.21: "Do not make Discover a generic shopping feed") — product surfaces belong to **Shopping**; this module links out to them rather than duplicating them.
- Community inspiration is explicitly deferred (spec §23 "Can follow shortly after" does not even list it — it's further out than that).

## Governing spec sections

§6.21 (screen spec), §28 (admin owns editorial content authoring; this module only renders what the admin tool publishes — no content-authoring UI belongs on-device).

## What already exists to build against

- No dedicated `Domain/Repositories` protocol exists for Discover yet. Editorial content (lookbooks, guides, brand spotlights) has no table in spec §9's data model — it's implicitly admin-authored content (§28) served some other way (a public Storage bucket, a CMS-backed Edge Function, or a `curated_content` table not yet specified). Whichever tickets pick this up should either extend `ShoppingRepository` (for the catalog-adjacent parts, e.g. brand spotlights) or introduce a small new protocol — this is flagged as a spec ambiguity in the top-level README.

## Tickets

Spec §8's repository list has no obvious owner for Discover, and the task-breakdown ID prefixes provided (P1-CORE, P2-ONBOARD, P3-CLOSET, P3-SCAN, P4-OUTFIT, P5-KYRA, P6-STUDIO, P6-SHOP, P7-SUB) don't include a Discover-specific one either. Most likely home: **P6-SHOP**, given the tight coupling to curated products and brand content — confirm against `docs/02-task-breakdown.md` once it's finalized.
