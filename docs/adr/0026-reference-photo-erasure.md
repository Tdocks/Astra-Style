# ADR 0026 — Atomic reference-photo erasure and abandoned-upload cleanup

Status: Accepted, 2026-10-08.

## Requirement

Spec §§13, 15 and 29 require individual image erasure, account ownership,
recoverable Storage deletion and configurable cleanup of abandoned sources.
Deleting only previews whose immediate source is the original photo leaves
variations behind. Client sequencing also lets a new generation race erasure
and used to restore an old whole-profile snapshot after a Storage failure.

## Decision

`DELETE /profile/reference-photos` authenticates the caller with Supabase Auth,
validates a bounded JSON body containing an owned UUID JPEG reference path,
and calls a service-only `SECURITY INVOKER` transaction. It locks the current
body-profile row, then the same per-user advisory lock as Studio enqueue,
then the reference path and owned generation rows. A recursive `UNION` follows
every derived result, including variations of variations without a page cap.
An active descendant rejects the whole operation before any mutation.

Accepted erasure hides every descendant, removes only the selected path from
the locked profile's current reference array, and queues immutable file paths.
Saved-look entries become invisible immediately and cascade when the underlying
generation is physically removed. Successful usage remains consumed. Duplicate
requests return the same owned cleanup job, including after file removal.

The existing fenced Storage API worker handles both output and reference jobs.
Their UUID keys have separate namespaces. Reference-path validation requires
the exact owner/key `.jpg` path and a null generation ID. Completion verifies
Storage metadata is absent; SQL never deletes production Storage metadata.
File failures remain pending and are retried by the five-minute scheduler.
Private snapshots and lease tokens are excluded from client grants and exports.
Safe owned status includes the job kind. The native reference screen continues
to show retryable cleanup status after its photo list becomes empty.

Retained reference-job keys are tombstones. Source-acceptance and body-profile
save guards take the same path lock and recheck tombstones after waiting,
preventing new jobs or stale profile saves from resurrecting an erased photo.
The body trigger has narrowly scoped definer authority to read queue keys;
its callable privilege is revoked from PUBLIC, anon and authenticated, and it
validates caller ownership. Other profile operations remain scoped by RLS.

Abandoned cleanup defaults to **24 hours**, configurable from 1 to 720 hours.
It selects UUID reference JPEG uploads whose creation **and last replacement**
are older than that window, with no saved body-profile reference and no visible
generation using them. A saved or used photo is preserved, including a failed
generation's source that may still be useful for retry. Protected files are
excluded before the batch limit, then protection and age are rechecked after
locking. Fresh uploads, closet photos and avatars are not candidates.
Automatic reference preparation was disabled during deployment verification;
the following activation migration enables it after worker deployment.

The new app uses the atomic endpoint; build 17 and earlier still use the older
client sequence. Their direct reference Storage removal is now denied, so any
reference they unlink without the new endpoint is eligible for the abandoned
policy only after its retention window. Install build 18 for coordinated,
immediate reference erasure and tracked background file removal.

## Verification

- All migration/RLS suites, including `34_reference_photo_cleanup.sql`, passed.
  Assertions cover ownership, recursive erasure, active-job atomic refusal,
  unrelated profile preservation, stale-save/source tombstones, direct Storage
  deletion denial, idempotency, Storage-completion fencing, protected/fresh
  upload retention, batch selection, duplicate preparation and account cascade.
- Two-session tests in `test-reference-cleanup-concurrency.py` passed both
  enqueue/erasure orderings and both profile-save/abandoned-sweep orderings.
  The existing generated-source deletion concurrency suite still passed.
- 89 Deno regression tests passed, including reference endpoint, scheduler,
  Studio, export, provider and CORS contracts. Type checks and lint passed.
- 18 Swift tests and both native reference-cascade UI flows passed on iOS 26.5
  iPhone 17 Pro Simulator in standard dark and light Accessibility XXXL layouts.
  The tests found and fixed a parent accessibility group overriding the delete
  button identifier. Screenshots are attached to the successful test result.

- Signed-in live acceptance passed direct RPC denial (403), peer-path rejection
  (400), missing-photo rejection (404), active-descendant refusal (409), accepted
  erasure (200), same-job duplicate response, stale profile rejection (400),
  unrelated photo/profile preservation, hidden saved memberships, and eventual
  physical removal of all three generation rows and their files. The scheduler
  returned 200 with three jobs completed and zero retries. The 28-table export
  returned four completed safe jobs, including one reference job; consumed
  credits stayed consumed. Both QA accounts and all their objects were erased.
- Activation's first live sweep returned 200 with four abandoned uploads
  prepared, four completed and zero retries. All four were older than 24 hours,
  belonged to existing accounts, and had no saved or visible generation use.
  The follow-up Storage query found zero reference objects remaining. No saved
  reference was selected; the synthetic saved-photo preservation check had
  already passed before that test account was deleted.
- The post-migration security advisor reports no publicly callable definer
  RPC. Existing anonymous-access notices are expected for the guest model;
  the private retention config has no client policy, and pg_net remains in its
  provider-managed extension location. Neither is made public to silence lint.

TestFlight 1.0.0 (18) is VALID and IN_BETA_TESTING in Internal, with membership confirmed. The final build-18 simulator run passed all eight core flows and both reference-removal flows (10 UI tests, zero failures); release details are in START_HERE.md.
Synthetic Storage objects establish erasure behavior, not image-provider
quality, face preservation or physical-device camera behavior. Previously
cached or downloaded image bytes are not remotely recallable; new reference
uploads use a 60-second cache lifetime and private access, and origin removal
was verified independently of CDN invalidation.
