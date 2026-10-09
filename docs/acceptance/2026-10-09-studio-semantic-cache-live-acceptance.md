# P6-STUDIO-07 hosted cache and retention acceptance

**Result: passed for hosted semantic cache and owner-photo deletion.** The run
used the deployed Studio function and migration `20261009080924` in the shared
production project, with disposable confirmed QA accounts and synthetic pixels.
No provider was called.

## Evidence

- `hosted_semantic_cache_acceptance.ts` created an opted-in request and uploaded
  a synthetic 1×1 PNG to the exact owner-scoped Studio result path. A second
  request with a fresh transport idempotency key returned the same completed
  generation ID. The owner's used allowance remained at one.
- A request with the semantic-cache opt-in omitted returned a distinct queued
  generation, proving the legacy-client compatibility path. An explicit
  variation nonce also returned a distinct queued generation. A second owner
  with the same request got a separate queued generation.
- The harness never called `GET /studio/status`; queued records could not
  trigger a provider render.
- The owner uploaded a synthetic JPEG reference, attached its path to the
  disposable body profile, and deleted it through `DELETE
  /profile/reference-photos`. The response completed; owner Storage listing
  showed no object, the profile no longer referenced the path, and the durable
  retention record completed with a null object path.
- Both accounts reached completed normal account deletion. Auth identity
  checks passed in the harness. Root independently confirmed zero rows in Auth,
  `studio_generations`, and Storage for both successful-run accounts.

## Retention scope

The local rollback SQL test `supabase/tests/48_studio_semantic_generation_cache.sql`
sets `retention_expires_at` and `cache_expires_at` into the past and proves
expired/missing/deleted result references are not reused. The hosted run proves
normal API-driven owner reference deletion and Storage removal. It did not
change the project-wide retention configuration or age any unrelated user's
data. It did not separately prove a hosted one-hour age selection; that is not
required by the ticket's artificial-short-window acceptance criterion.

`49_studio_reference_short_retention.sql` separately passed in scratch Postgres:
a transaction-local one-hour window selected a two-hour-old synthetic reference,
claimed its cleanup job, and finalized deletion with its private path cleared.
The retention worker test `short-window abandoned reference uses the same
Storage-before-finalization fence` verifies the Storage API removal precedes
successful database finalization. The full scratch migration/RLS run passed;
the shared production retention settings were unchanged.

Native verification on 2026-10-09 passed 1,101 Swift Testing tests and 33 XCTest
tests, including explicit Studio reroll/retry behavior. This establishes client
opt-in and reroll behavior alongside the hosted cache evidence above.

## Disposable-run cleanup

Successful run owner: `2e85ac91-372f-4dd1-b4da-ca69adca31bc`.
Successful run peer: `15dda044-4443-47bc-8099-61316942c10a`.

An earlier failed verification attempt still ran the `finally` cleanup, but
the then-current harness did not log its IDs on failure. The second failed
attempt's owner/peer IDs were provided to root and root confirmed their Auth,
generation, and Storage counts are zero. No credentials are stored in this
document.

## Reproduction

After verifying the target project has the required migration and deployed
function, run this opt-in script with `SUPABASE_URL`, a protected
`SUPABASE_KEYS_FILE` containing the CLI's JSON key list, and
`ASTRA_ALLOW_DISPOSABLE_STUDIO_CACHE_ACCEPTANCE=YES`. The script prints no API
keys or access tokens and removes its temporary protected key file in the
invocation wrapper's exit trap.
