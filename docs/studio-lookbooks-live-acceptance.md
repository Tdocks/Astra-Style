# Private Studio collections — 2026-10-08

## Implemented

- Studio opens private Saved looks; users can create, rename and remove collections.
- A completed estimate can be saved in several collections from its detail screen.
  Duplicate saves are idempotent; the picker shows saved membership and permits removal.
- Collections and their contents use stable server pagination. Images resolve
  through the existing private URL resolver and mandatory estimate container.
- Saving explicitly exempts the estimate from expiry. Removing the final save
  resets a 30-day unsaved window; collection deletion does not delete its estimates.
- Owned generation/account deletion cascades entries. Consumption records remain
  unaffected by collection edits or individual estimate deletion.

See [ADR 0023](adr/0023-private-studio-lookbooks.md). Migration
`20261008213738_studio_saved_lookbooks.sql` is deployed, matching hosted history.
Studio v10 and Profile v12 expose the retention timestamp and export the new tables.

## Evidence

- Seven Swift unit tests passed: bounded names, create/save/remove, retry without
  duplicate empty collections, both pagination paths, rename/delete, signing
  failures and unavailable/peer-image rejection in the offline repository.
- A subsequent serial Studio regression run passed 26 tests across five suites
  and exited with `TEST EXECUTE SUCCEEDED`.
- Serial simulator flows passed generation → save → create collection →
  reopen collection → remove look → empty collection, including light theme
  at Accessibility XXXL. They use mock imagery.
- The scratch Postgres suite passed the existing 155 RLS assertions, Studio job
  safety checks and new collection checks. These assert actual owner policies,
  composite parent ownership, immutable entries, unfinished-image rejection,
  save/remove retention transitions, duplicate saves and account-erasure cascades.
- Studio/provider/export regression tests passed: 62 tests, zero failures.
- Live acceptance used two disposable anonymous identities. A real provider
  generation completed with an unsaved expiry. Owned duplicate saves returned a
  single nested generation through the exact relation join used by the native
  repository. Saving cleared expiry; removing one of two saves retained it;
  deleting the final collection restored expiry.
- Peer collection reads and rename attempts returned no rows. Linking a peer
  generation was rejected with HTTP 403; linking an owned generation to a peer
  collection was rejected with HTTP 409 by the composite ownership constraint.
- Export returned 27 tables and only the caller's collections/entries. Both QA
  deletion requests completed; no QA auth identities remained.

The security advisor's new collection notices are the same anonymous-identity
access warning as existing owner-scoped tables; the two-user checks above prove
ownership isolation. The service-only pending App Store notification table still
has intentional RLS with no client policy. Review anonymous access alongside
quotas using [Supabase's advisory](https://supabase.com/docs/guides/database/database-advisors?queryGroups=lint&lint=0012_auth_allow_anonymous_sign_ins).

## Remaining

- A scheduled Storage API sweep must enforce expiration; a timestamp alone is
  not automatic deletion. Saved estimates and source-image dependencies must be
  protected when implementing that sweep.
- Editable image descriptions, high-resolution generation/export, monthly
  Premium limits and full device image-fidelity acceptance remain separate work.
- Internal build 15 predates the collection UI. The next build will include it;
  do not attribute these native screens to build 15.
