# ADR 0045 — Admin-only compatibility weight updates

Status: Accepted  
Date: 2026-10-09

## Context

ADR 0040 intentionally kept the global compatibility weights behind the
service role and left an administrative editing interface out of scope. The
P4-OUTFIT-03 acceptance criteria require an administrator to change the
weights without a client release and have subsequent scoring requests use
the updated values. This ADR supersedes only ADR 0040's decision to omit that
editing interface; the service-only table boundary remains in force.

## Decision

Expose `POST /outfits/config/compatibility-weights`. The endpoint calls
Supabase Auth `getUser` with the request's bearer token on every request and
allows only a non-anonymous user whose server-returned
`app_metadata.astra_admin` is exactly `true`. It never reads
`user_metadata`, a client-supplied role, or unverified JWT claims for
authorization. Admin metadata is provisioned only through the trusted
Supabase Admin API by an operator; this change promotes no existing account
and adds no client-facing role-management path.

The request supplies all eight known finite weights in `[0, 1]`, a sum of
`1.0` within `1e-6`, and the current expected configuration version. A
service-role client performs a compare-and-swap update on the singleton row.
The database trigger increments the version when weights change and preserves
it for an identical update. A stale expected version returns HTTP 409. The
database constraint enforces the same key, range, and sum rules. Ordinary
client roles retain no update privileges on `compatibility_weights_config`.

## Consequences

Scoring requests continue to load weights through the service-only config
reader; wardrobe data continues to use caller-scoped reads. Updating the
singleton changes the weight vector observed by later scoring requests and
its version remains available to cache-key logic. The endpoint logs outcome
and version, not the request's weight payload.

## Verification and limits

Unit tests cover fresh Auth verification, missing/invalid/non-admin and
anonymous callers, rejection of user-controlled metadata, schema/range/sum
validation, compare-and-swap conflicts, no-op version stability, and a
successful update followed by a config re-fetch that changes the scorer's
result. Hosted acceptance passed on 2026-10-09: no-op 200/version 1, stale 409,
invalid sum 400, nonadmin metadata spoof and anonymous 403, missing auth 401.
Production weights were unchanged. All three disposable accounts were deleted
through the normal endpoint; independent SQL confirmed zero Auth/profile rows
and three completed deletion jobs. No existing user was promoted.
