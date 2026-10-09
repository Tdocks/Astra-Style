# 0034 — Full-look mirror references

Date: 2026-10-08

## Decision

P3-SCAN-12's mirror mode captures/imports a complete photo and associates it with the user's existing private appearance reference-photo collection. It does not infer measurements, segment garments or generate an image. The screen describes that purpose and requires permission before saving. Studio still requires its own terms-versioned generation consent; saving a mirror reference does not create a Studio consent receipt.

Reuse ProfileRepository and ReferenceImagePreparation rather than introducing another photo table or deletion system. Photos appear in Profile → Reference Photos and use its existing coordinated deletion and export behavior. Preparation resizes and re-encodes the photo. The scanner and Closet menus expose the mode.

The view model verifies the body profile owner, verifies the returned private reference path's owner and checks the current account again before association. A failed profile write retains the uploaded path for retry rather than repeatedly uploading the photo. Association uses a caller-scoped database RPC that locks the current body row and appends the reference without rewriting other body fields. Mock uploads now return the mock profile's real owner path.

## Remaining acceptance and risks

Simulator build and strict lint passed. Three native workflow tests passed: permission gating and body-field preservation, deletion through the reference repository, failed-association retry reusing the path, and invalid-image rejection. Live permanent-account upload/deletion/export, camera/Photos UI, large text and physical-device acceptance remain open. Guest photo uploads remain server-denied.

The current upload and body-profile association are separate operations. Abandoned unassociated references rely on the existing 24-hour retention sweep. The atomic association endpoint rejects missing uploaded objects and cleanup tombstones and deduplicates retries. An authenticated profile-edit trigger preserves previously associated reference paths, preventing later stale snapshots from discarding them. Explicit removal continues through the service-role coordinated deletion endpoint. Tombstone validation still rejects resurrection attempts. TestFlight remains build 22 and does not contain this scanner batch.
