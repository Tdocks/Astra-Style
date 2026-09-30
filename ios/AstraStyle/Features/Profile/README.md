# Profile

Owns the Profile tab: identity, stats, Style Journey, and privacy controls (spec section 6.22 and 6.23).

## Privacy & Data

- Account deletion is implemented in-app.
- Style-memory review/deletion and reference-photo deletion are available. Reference-photo removal also removes related Studio generations and result images.
- Personal-data export is implemented locally: GET /profile/export-data returns profile and user-owned app records as versioned JSON. The signed-in user's JWT and RLS scope each table query; the response is paged to avoid the PostgREST row cap. The app writes a protected temporary file and opens the iOS share sheet.
- Profile portraits use the same private `user-content` bucket, store only `avatar_storage_path`, and resolve a short-lived signed URL on display. `20260930111500_profile_avatar_storage_path.sql` must be applied before this client flow is released.
- The export excludes shared catalog rows, internal idempotency records, and storage image bytes. Closet/reference image paths and metadata plus monthly Wardrobe Score baselines are included as user-owned table data.
- The hosted Edge Function has not been deployed from this checkout, and live RLS/completeness acceptance remains open. P7-PRIVACY-03 is therefore Partial until that verification is complete.
- Legal pages still contain unresolved business and counsel inputs. They remain drafts and block outside-user release.

## Module

- `ProfileView.swift` — identity, About, wardrobe score summary, shopping stats, profile and privacy links.
- `Views/ProfileDashboardView.swift` — current closet/outfit totals, cost per wear, monthly spend grouped by currency, most-worn colors, and a recent Style Journey timeline.
- `Views/ProfileIdentityCard.swift` / `ViewModels/ProfileIdentityViewModel.swift` — optional profile portrait upload, private signed display, replacement, and removal.
- `Views/WardrobeScoreView.swift` — live score summary, empty/error states, and the seven-component detail view. It uses only the `ClosetRepository` protocol and displays component values with a data-quality note.
- `Views/SubscriptionManagementView.swift` — server-reconciled plan status, Apple subscription management link, Premium entry, and StoreKit restore.
- `ViewModels/SubscriptionManagementViewModel.swift` — fetches current plan and restores verified transactions through the server repository.
- `ViewModels/WardrobeScoreViewModel` (co-located with the view) — loading, retry, and repository error state.
- Routing/ProfileDestinationView.swift — dependency composition for profile destinations.
- Views/PrivacyAndDataView.swift — Style Memories, Reference Photos, Export My Data, and Delete My Account.
- ViewModels/PersonalDataExportViewModel.swift — export progress/error and shareable local file state.
- ReferencePhotosView and AccountDeletionView — personal photo and account removal flows.

## Governing specification

Spec sections 6.22–6.23, 9, 15, 29, and 30.
