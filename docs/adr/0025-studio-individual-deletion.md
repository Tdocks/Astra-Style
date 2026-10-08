# 0025. Server-owned individual Studio deletion

## Status

Accepted — 2026-10-08. Extends ADR 0024, implements §6.17 and §29.

## Decision

Individual deletion uses the same durable queue and Storage API verification as
expiration. `DELETE /studio/generations/:id` authenticates against Supabase Auth,
then calls service-only, invoker RPCs with the verified owner. The client no longer
removes a file before checking its generation's dependencies.

- Preparation locks the generation and rejects active jobs or images used by a
  live variation. The source-insertion guard locks the same row and rechecks it.
- Accepted deletions hide the preview and saved entries immediately. A specific
  leased job removes the file through Storage API, verifies its metadata is absent,
  then deletes the generation and cascades collection membership. A successful
  allowance remains consumed. Repeated requests return the same cleanup job.
- Failed file removal returns accepted/pending metadata. The five-minute worker
  recovers the persisted job and expired leases. Studio displays unfinished removal
  and offers a status refresh, including when its gallery becomes empty.
- Authenticated clients cannot directly delete Studio generation rows or files.
  Existing owner Storage policies for other image categories are unchanged.
- No client receives a privileged Storage path or lease token. Export includes only
  the existing safe, owner-scoped cleanup columns.
- The expiration worker also rechecks source dependencies after acquiring a lock,
  just as it already rechecks saved membership.

Older builds through 16 use the former direct deletion path and cannot delete
Studio outputs after this migration. The next native build uses this endpoint.
This deliberate compatibility change prevents the old path from bypassing the
dependency check. Creating, viewing, sharing and saving estimates remain available.

## Cache behavior

Removal at the origin and invalidation of an already cached URL are separate.
The live check initially observed HTTP 200 for the cached test image after its
file/row removal; a fresh `cacheNonce` request returned HTTP 400/not found and the
original URL later returned not found after invalidation. Supabase documents
[up to 60 seconds for CDN invalidation](https://supabase.com/docs/guides/storage/cdn/smart-cdn).
New generated uploads use a 60-second client cache TTL. The app clears gallery
image state on accepted removal. Completion means verified origin removal, not
erasure of previously downloaded/exported copies.

## Verification

- SQL isolation harness: existing 155 assertions plus job, collection, retention
  and individual-deletion checks passed. It checks server-only grants, source
  dependencies, active jobs, idempotency, leases, direct Storage deletion denial,
  hidden saves, no rerolls against deleted sources, retained allowance and erasure.
- `scripts/test-studio-deletion-concurrency.py`: two real concurrent PostgreSQL
  sessions prove both lock orderings. A new source insertion makes waiting deletion
  refuse the parent; deletion makes a waiting insertion reject its hidden source.
  Automatic expiry also preserves the committed dependent source.
- Deno Studio, retention, export and live image adapter regression: 77 passed.
- Swift Studio and endpoint suites: 34 tests passed across six suites.
- Simulator accepted-removal and pending-status flows passed in standard dark
  mode and light Accessibility XXXL. The empty state is now scrollable and its
  primary label wraps instead of truncating. Native build 17 contains the endpoint
  change; TestFlight processing is verified separately in START_HERE.
- Authenticated disposable live accounts: direct row/RPC writes 403, direct file
  deletion preserved the file, peer/missing deletion 404, active/dependent deletion
  409, saved-child deletion 200, duplicate returned the same completed job, saved
  membership disappeared, parent and failed/no-output removals completed, peer
  metadata stayed hidden, and export contained three safe completed cleanup jobs.
  Both accounts reached completed erasure; remaining users, objects and jobs were 0.
- Studio is deployed ACTIVE v13, JWT verification enabled. The live deletion check
  ran against v12; v13 only adds the documented upload cache TTL.

## Remaining work

The Supabase advisor scan was rechecked. Private server-only config/notification
tables intentionally have RLS and no consumer policies. Owner-isolated anonymous
authenticated users remain allowed by the existing account design. The newly
installed `pg_net` extension reports its public metadata namespace and is not
relocatable; no system-catalog rewrite or extension drop was attempted. Cron's
extension-owned PUBLIC table/function grants cannot all be revoked by the project's
`postgres` role, but its schema USAGE grant was successfully removed from consumer
roles: an actual authenticated SQL lookup of `cron.job` was denied. Vault reads are
also denied. The scheduler still runs as postgres. These advisor notices are
reviewed conditions, not a claim of a clean advisor report.
The scheduled run after the schema-grant change succeeded at 22:25 UTC and its
HTTP request returned 200 without a timeout.

Abandoned reference cleanup, editable alt descriptions, high-resolution renders,
Premium quantity controls, real-device sharing/image acceptance and counsel inputs
remain outside this deletion batch. No claim of complete Studio or launch readiness.
