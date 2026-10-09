# Closet batch retry and worker ownership acceptance

## Deployed database and function

Migration `20261009221435_closet_batch_job_idempotency` adds an owner-unique
enqueue key, canonical request fingerprint and expiring worker claim. Production
readback confirmed all four columns, the unique index and RLS. Authenticated
clients retain only owner-scoped SELECT; direct client writes, TRUNCATE,
REFERENCES and TRIGGER privileges are revoked. Anonymous table access is
revoked. The authenticated Edge Function uses the service client with an
explicit owner filter on every job operation. Account deletion still cascades.

Closet v25 was deployed ACTIVE with JWT verification enabled. Identical enqueue
retries return the original job; changed bodies return 409. Concurrent polls
claim at most one worker; an expired worker cannot commit over a new claim.
The lease is 60 seconds, longer than the 20-second provider deadline.

## Verification

- Full backend suite passed 1,084 tests before the final grant tightening.
  The focused handler suite then passed 17 tests, including replay after the
  new-job rate limit is exhausted. Formatting, lint and type checking passed.
- Fresh scratch migration/RLS suite passed through SQL test 58 with the final
  grant restriction. It checks owner identity, replay uniqueness, lease expiry,
  stale worker denial and privileged client operations.
- `supabase/functions/closet/hosted_batch_idempotency_acceptance.ts` passed
  against production: same-key replay 202/same job, changed body 409, peer
  status 404, owner SELECT one row, peer SELECT zero rows, direct client
  INSERT/PATCH/DELETE all 403, and the owned row unchanged. A shared key across
  owners produced distinct jobs.
- This metadata-only run uploaded no images, polled no owned jobs and invoked
  no provider. It does not measure garment recognition accuracy.
- Both fixtures were deleted through the normal account endpoint. Root
  independently confirmed zero Auth users, profiles, batch jobs and Storage
  objects for those IDs; both deletion receipts were completed. The first
  harness attempt failed on a redundant cancellation of an already-consumed
  response body; its separate fixtures were also independently cleaned.
- The security advisor retains its existing 18 INFO/35 WARN findings; this
  is not a clean advisor scan or an external-user readiness declaration.

Report: `/tmp/astra-closet-batch-acceptance-result.json`.
Function readback: `/tmp/astra-priority-batch-function-list.json`.

## Safe cancellation acceptance

POST `/closet/batch-cancel` is authenticated and independent of provider configuration. A cancellation before enqueue creates an owner-scoped tombstone so a late request cannot start work on deleted photos. Cancellation during a live worker lease returns a conflict and retains photos. Terminal results survive a completion race.

The expanded hosted harness passed with zero image uploads/provider calls/owned-job polls: cancellation before enqueue and replay returned 200; late enqueue returned 409; peer cancellation left the owner’s job unchanged; queued cancellation and replay returned 200 and a failed empty job. Independent readback found zero fixture Auth users, profiles, jobs and Storage objects and both deletion receipts completed. Report: `/tmp/astra-priority-cancel-live.json`.

The final full backend suite passed 1,087 tests; focused Closet handler suite passed 20. Fresh scratch migration/RLS assertions passed through SQL test 58.

## Remaining scanner acceptance

Native relaunch recovery and safe explicit abandonment are being completed
in the coordinated scanner pass. Real garment photographs, correction/save
acceptance, representative-photo accuracy and physical camera checks remain
separate requirements. Backend metadata checks cannot establish those results.
