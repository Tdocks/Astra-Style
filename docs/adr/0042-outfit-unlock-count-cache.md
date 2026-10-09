# ADR 0042: Persisted cache for unchanged outfit-unlock inputs

**Status:** Accepted (deployment pending review)  
**Date:** 2026-10-09

## Context

P4-OUTFIT-09 defines a 30-day cache keyed by the authenticated user, a normalized candidate, the closet state version, and the compatibility-weight version. The production `/products/evaluate` and `/products/unlocks` routes were calling `computeUnlockCount` on every request. Repeated unchanged requests therefore repeated anchored outfit generation, and the old helper in `unlockCount.ts` was not connected to storage.

The documented minimum key omits live inputs now read by the scorer. The selected wardrobe graph changes required roles; scoring context and weights change outfit quality and gap results. The scorer also reads closet attributes beyond the original candidate projection. Cache identity must include those inputs or their complete version, so the implementation extends the documented key rather than allowing an old result to survive a scoring change.

## Decision

Persist only the `UnlockCountResult`, not a full product evaluation or verdict. Compatibility, redundancy, affordability, lifestyle fit, and verdict are recomputed on each evaluation. Each request still appends its own `user_product_evaluations` history row.

Cache keys are SHA-256 over canonical JSON, version-tagged as `unlock-count-v2`, with:

- authenticated user ID (taken from the verified JWT path, never request JSON);
- candidate scoring attributes, excluding candidate ID and wear state;
- closet state version;
- compatibility-weight version and the actual weight vector;
- all supplied scoring context, including graph, weather, preferences, co-wear maps, and occasion where present.

The per-user database version advances on closet insert/delete and changes to fields used by scoring: category, primary/secondary colors, pattern, material, fit, seasonality, formality, warmth, water resistance, and archive state. Reads are ordered by stable closet item ID so the scorer's bounded sample is reproducible. `laundry_state` and `availability_state` are deliberately excluded: hypothetical purchase unlock counts model ownership, not whether an owned item is wearable today. These fields are not in the key and do not advance the counter.

The handler reads the version before fetching the closet. Before using a hit and again before publishing a miss, it verifies that the version still matches that snapshot. A version change bypasses the cache and prevents publishing the computed result. A later request reads and scores the new closet version.

Cache rows are service-role-only, owner-scoped by `(user_id, cache_key)`, and cascade with auth account deletion. Entries expire after 30 days. The service-only purge RPC removes at most 500 expired rows per call; writes request a bounded batch of 100. Cache read/write failure does not fail the user's scoring request.

## Consequences

- Repeated requests for the same candidate, wardrobe version, graph, and scorer configuration can reuse the full unlock result including gap details and degraded signals.
- A changed scoring context or weights vector cannot alias an earlier result even if a version bump is missed.
- Closet mutations prevent stale cache publication; a cache entry for an old closet version is unreachable after the version increments and is eventually purged.
- The cache remains an optimization only. It does not change verdict history, request identity, or product candidate storage.
- The cache key hashes personal context and wardrobe attributes; raw attributes are not duplicated in the cache table.
- The existing §6.6 synchronous compute budget remains unchanged. This ADR does not add asynchronous computation or timeout behavior.

## Verification requirements

Tests must cover hit reuse without recomputation, miss storage, input/context key separation, bypass on a closet version race, laundry/availability no-invalidation, scoring-field invalidation, service-only access, bounded expiry purge, and account deletion cascade. Deployment and hosted verification are intentionally outside this implementation task.
