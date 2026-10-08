# 0024. Recoverable Studio output expiration

## Status

Accepted and deployed, 2026-10-08. Implements generated-output retention in
master spec §13 / ADR 0010. Abandoned reference upload cleanup remains separate.

## Decision

- Private `studio_retention_config` controls activation and the output window
  (30 days by default, bounded to 1–365 days). The window starts at completion;
  removing the final collection save starts a fresh configured window.
- Explicitly saved estimates are permanent. Expiration also preserves an image
  used as another live generation's reference. Save and generated-source inserts
  lock and validate the current generation, serializing them with expiration.
- A service-only prepare RPC locks expired terminal generations, rechecks saves,
  hides them and snapshots their owned result paths into a deletion queue.
  Claim tokens and 180-second leases prevent normal duplicate workers and fence
  completion. Failed removal retries after five minutes.
- The worker validates the exact owned generation result path and uses the
  Storage API. Finalization verifies that `storage.objects` no longer contains
  the result, then removes the generation. It never directly deletes Storage
  metadata. Completed queue records clear result paths and claim tokens.
- The queue retains an immutable generation key even if the generation's FK is
  cleared by another deletion. This permits recovery of the snapshotted owned
  Storage path. Account deletion cascades all queue records.
- Users may read/export only their safe queue status columns; result paths and
  lease tokens are not granted. Global scheduler configuration is never exported.
- Supabase Cron invokes the worker every five minutes through pg_net. A random
  dedicated credential is encrypted in Vault; only its digest is in the config.
  No credential is committed, returned by setup, embedded in cron SQL or sent to
  the app. JWT verification is disabled specifically for this endpoint because
  the body verifies that scheduler credential before any privileged work.

Scheduling follows [Supabase's documented Cron / pg_net / Vault pattern](https://supabase.com/docs/guides/functions/schedule-functions).
The hosted-only extension installation is conditional in migration replay because
scratch Postgres CI lacks these Supabase extensions. Core SQL is tested there;
the real hosted scheduler and HTTP result are verified separately.

## Evidence

- Scratch SQL passed 155 existing RLS assertions, Studio job/collection checks,
  and retention checks for authorization, saved/dependent protection, idempotent
  preparation, leases, rejected post-expiration saves, owner-only metadata,
  Storage verification, retry backoff, consumed-credit preservation, configured
  windows and account erasure.
- Seven worker tests passed, including method/auth rejection, strict path fences,
  Storage-before-finalization order and recoverable removal failures.
- Two disposable live identities uploaded four synthetic PNGs. A controlled
  expired result was removed; a saved result and a parent/child source chain
  remained readable. Ordinary caller access returned 401 and direct prepare RPC
  access 403. Peer queue metadata was hidden. Export returned 28 tables with safe
  owned job metadata and no scheduler config/token/path exposure.
- The manually dispatched worker returned HTTP 200 with one prepared/completed
  result. The actual 21:55 UTC Cron run succeeded and its HTTP request returned
  200 without timeout. All pre-existing estimates were ineligible for expiry
  when the scheduler was enabled.
- Both QA account deletions completed; no QA auth identities, storage objects
  or queue records remained.

## Operational checks

Check `cron.job` for `astra-studio-retention-5m`, its recent `cron.job_run_details`,
and the corresponding `net._http_response` HTTP status. Cron SQL success alone
does not prove HTTP success. Inspect pending queue age/attempts without logging
private paths or scheduler credentials. Disable the config's `enabled` field to
stop job work while diagnosing a problem; saved collections remain intact.

## Remaining work

- Abandoned reference uploads need their 24-hour configurable cleanup, preserving
  saved body-profile references and generation dependencies.
- Manual Studio deletion still uses the native Storage-then-row sequence. Move it
  to server-owned preparation/finalization to apply the same dependency and race
  protections; do not treat this expiration worker as proof of that separate path.
- Editable alt descriptions, Premium monthly limits, high-resolution generation,
  populated export attachments and real-device acceptance remain open.

Deployment migrations: `20261008215219_studio_retention_queue.sql`, `20261008215307_studio_retention_schedule.sql`, and `20261008215653_studio_retention_window.sql`; local versions match hosted history.
