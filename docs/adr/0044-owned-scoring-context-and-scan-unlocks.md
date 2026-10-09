# ADR 0044 — Owned scoring context and saved-item unlock counts

Status: Accepted (2026-10-09); deployment and native acceptance are tracked separately.

## Decision

Outfit generation, product evaluation, Discover Unlocks, and scanner unlock reports
share the canonical preference and co-wear context loader. Reads use the authenticated
owner, explicit owner predicates, and stable pagination. Preferred/avoided color,
fit, and formality come from the saved style profile. Rated wear history contributes
exact garment-pair and role-pair signals, with ratings of at least three treated as
positive. Missing signals retain the scorer's existing cold-start behavior.

Product scoring does not invent an occasion or current weather. Its cache key hashes
the supplied full context, so preferences and history changes invalidate results
without abusing the closet mutation counter. Current weather and authorized calendar
context remain inputs to today's native outfit-generation request.

The scanner queries GET /closet/items/:id/unlock-count after a successful save.
The endpoint resolves the saved item's attributes from the owner's active closet,
removes that item from the comparison pool, and invokes the same hypothetical
ownership algorithm as products. Keeping the saved item in the pool would make it
its own equivalent substitute and incorrectly suppress its count.

Unsupported categories return unmeasurable rather than zero. Missing, archived,
and peer-owned items return the same unavailable response. Network/count failures
preserve successful saves and present a separate retryable report state. Offline
queued saves must synchronize before a server count can be obtained. The free-tier
repository wrapper forwards this report without adding a Premium gate.

## Limits

A count describes plausible algorithmic combinations, not rendered images or a
promise that every combination is appropriate for a specific event. These changes
perform no provider image request, disclose no calendar event title/location, and
add no model-training permission. Live endpoint, cache, simulator, and device
acceptance remain independent gates; targeted tests cannot establish them all.
