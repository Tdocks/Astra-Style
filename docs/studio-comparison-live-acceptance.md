# Studio comparison and live acceptance — 2026-10-08

## Implemented

- Compare two completed private estimates from Studio, or compare a generated estimate with its original reference from detail.
- Optional original images, explicit estimate disclaimer, full-image rendering, retryable signing failures, and vertical layout at accessibility text sizes.
- Refresh gallery when returning to Studio and dismissing generation. Revision guards prevent stale signed-image work from replacing refreshed pages. Deletion preserves pages loaded concurrently.

## Live backend acceptance

Simulator verification: build succeeded; nine comparison/gallery unit tests passed; standard comparison UI flow passed; the light-theme comparison flow at Accessibility XXXL passed after simplifying selection cards to avoid crowded image/text controls. Account/export backend suites passed 26 tests. UI images in these simulator flows use mocks, so real image fidelity is covered only by the separate provider check below.

The deployed backend was exercised through authenticated requests using disposable anonymous accounts. Owner wardrobe data was not used.

- Two inspiration generations completed through the real image provider; private storage signing returned PNG images. Synthetic weather/style context was supplied. This verifies the provider path, not real-device WeatherKit or calendar permission integration.
- Kyra returned HTTP 200 with a structured assistant response to a cool/rainy-day styling question.
- Export initially returned HTTP 500 because the analytics table was absent despite the original migration appearing in deployment history. Reapplying its definitions restored HTTP 200; `20261008203730_restore_analytics_events.sql` records this repair without editing the original migration.
- Two-user export acceptance returned 24 tables, included the caller's activity fixture, excluded the other user's activity, and rejected an attempted cross-user activity insert (HTTP 403).
- Cleanup exposed a second production failure: `finalize_account_deletion` directly deleted `storage.objects`, now rejected by Supabase. The append-only `20261008203918_account_deletion_storage_api_only.sql` replaces that deletion with verification that the Storage API removed all files, retaining service-role-only execution.
- Both original image-test accounts were cleaned after the repair. Two subsequent account-deletion requests completed through the deployed handler. All four deletion records were verified completed.

## Image sharing after build 13

Completed estimates can prepare a protected local PNG and share it through the system share sheet. The exporter renews the private URL and rechecks that the generation remains completed and undeleted before downloading. It retains the full image and adds an AI visual-estimate footer; it does not request a new high-resolution render. Old temporary export files expire on a subsequent export after 24 hours. Tests cover rendering a valid PNG/footer, invalid downloads, deletion after loading, recoverable export errors, and the simulator path to an enabled Share button. The simulator path uses an explicitly labeled offline preview fixture. Real-device share destinations remain acceptance work.

Comparison now retains the user's selection order. Detail images use the shared image component so an image download failure displays a fallback rather than an endless spinner.

The final combined run reported six export unit tests and both comparison/sharing UI tests passed, but Xcode stalled in teardown. After stopping only the stalled test processes, a serial `test-without-building` sharing run finished with `TEST EXECUTE SUCCEEDED` (2026-10-08 16:53 EDT). Prefer `-parallel-testing-enabled NO` for this owner's Xcode 27 simulator acceptance runs when teardown stalls recur. This is not a complete application walkthrough.

## Server job safety follow-up — deployed

The subsequent batch closed the free-trial counting, direct-write and concurrent-submission gaps using server-only job writes, durable success-based allowances, idempotent retries, and fenced claims. Studio v9 and Profile v11 are deployed. See [ADR 0022](adr/0022-studio-server-jobs-and-allowances.md) for rollout, tests, live acceptance and limits. Configurable Premium monthly limits and high-resolution generation remain work. Private collections were subsequently implemented; see [collection acceptance](studio-lookbooks-live-acceptance.md).

The post-migration advisor scan found anonymous-identity access warnings on owner-scoped policies, rather than a missing ownership predicate. Review that access alongside provider quotas; see [Supabase's anonymous access advisory](https://supabase.com/docs/guides/database/database-advisors?queryGroups=lint&lint=0012_auth_allow_anonymous_sign_ins). The pending App Store notification table intentionally has RLS with no client policy and is service-only. Performance notices were unused indexes and Auth connection allocation; no indexes were removed based on this low-traffic sample.

## Remaining acceptance

- Private reference-photo comparison and closet image fidelity need device acceptance.
- Export with a populated wardrobe, attachment files, and more than 500 rows needs completeness checks.
- Higher-resolution export and scheduled image retention remain open; private collection save/remove is covered by the subsequent acceptance report.
- Real camera, voice, purchases, weather/location and calendar permission checks remain device work.
- No claim of outside-user readiness follows from this batch.

## Generated-image disclosure follow-up

The detail, comparison and gallery surfaces now use `GeneratedImageContainer`.
Real reference photos remain unbadged; inspiration reroll sources are labeled as
previous visual estimates. Small gallery images place the disclosure below the
thumbnail, and accessibility text sizes omit thumbnails to leave room for the
text. Home's styling entry cards also give accessibility text the full card width.

Serial simulator comparison checks passed in standard and light Accessibility
XXXL layouts, now asserting that both previews expose their disclosures. The
detail assertion initially found identifier propagation from the container to
the badge. Moving the image identifier onto the image corrected that issue; the
sharing/detail recheck exited with `TEST SUCCEEDED` and verified the separate
disclosure plus the enabled Share action. Image fidelity remains outside these
mock-backed UI checks.

Build 14 was independently verified VALID / IN_BETA_TESTING in the Internal
group on 2026-10-08. It includes comparison and image-file sharing. The disclosure
and Home accessibility adjustments above follow that archive and are not in
build 14.

Build 15 was subsequently verified VALID / IN_BETA_TESTING with Internal membership, including the disclosure and accessibility follow-up. Collection screens follow build 15.
