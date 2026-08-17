# Profile

Owns the Profile tab: identity, stats, Style Journey, and privacy controls (spec §6.22, §6.23).

## What this module owns, and what has actually been built

`P7-PRIVACY-02` (in-app account deletion) and `P7-PRIVACY-03` (personal data export) are the
only two tickets built here so far — both App Store Guideline 5.1.1(v)/spec §15/§29 gates for
shipping to any external tester. Everything else this module will eventually own (profile
header, Style DNA summary, Wardrobe Score, items owned, outfits created, cost per wear,
most-worn colors, monthly spend, Style Journey timeline, subscription status, preferences) is
`P7-HOME-05` and other later tickets, and is deliberately NOT here yet — see `ProfileView.swift`'s
header for why a stats dashboard was not built to fill the space.

- `ProfileView.swift` — the tab root. One row: "Privacy & Data".
- `Routing/ProfileDestinationView.swift` — resolves `ProfileRoute`. Two cases are real
  (`.privacyAndData`, `.accountDeletion`); the other six are honest `FeaturePlaceholderView`s for
  screens owned by other tickets.
- `Views/PrivacyAndDataView.swift` — one row, "Delete My Account". See its header for why there is
  no export row and no per-image/style-memory row.
- `Views/AccountDeletionView.swift` + `ViewModels/AccountDeletionViewModel.swift` — the deletion
  confirmation flow: what gets destroyed (transcribed from
  `supabase/migrations/20260728101300_account_deletion.sql`'s header), an explicit acknowledgment
  toggle plus a destructive confirmation dialog, and a terminal "deletion started, you're signed
  out" screen that never claims the deletion has finished — see that view model's header for why
  it structurally cannot.

## P7-PRIVACY-03 status: NOT satisfied

`ProfileRepository.exportPersonalData()` exists on the protocol and `LiveProfileRepository`
implements it, but its own header says what it actually does: sign a URL for
`exports/users/{uid}/export-latest.json`, an object nothing in this codebase ever writes. There is
no export Edge Function, no scheduled job, and no `exports` storage bucket in any migration. A
button calling it today would fail every time — spec §22's "no dead buttons" rule — so no export UI
was built. Making P7-PRIVACY-03 real requires, at minimum: an Edge Function or scheduled job that
actually produces `export-latest.json` per user (profile, closet, outfits, and Kyra conversation
history per spec §29), and the `exports` bucket + its RLS/storage policies. Once that exists, the
UI is a single row in `PrivacyAndDataView.swift` calling the existing repository method.

## Governing spec sections

§6.22-§6.23 (screen specs), §9 (`profiles`), §10 (Wardrobe Score display), §15 (account deletion must remove DB rows, storage objects, generated images, embeddings, style memories, and the auth identity), §29 (privacy/legal requirements), §30 (Definition of Done items 13-14: view/delete style memories, delete the account).

## What already exists to build against

- `Domain/Repositories/ProfileRepository.swift` — `exportPersonalData()` (not wired to a real backend — see above).
- `Domain/Repositories/AuthRepository.swift` — `deleteAccount() async throws -> AccountDeletionStatus` (built and wired to `DELETE /account`).
- `Domain/Models/AccountDeletionStatus.swift` — the `DELETE /account` response DTO, and why its `status` can only ever be `.pending`/`.processing`.
- `Domain/Repositories/KyraRepository.swift` — `fetchMemories()` / `deleteMemory(id:)` for the memory inspector, reached from Profile but not built by this pass (part of `P5-KYRA-17`).
- `Domain/Repositories/ClosetRepository.swift` — `fetchWardrobeScore()`, for `P7-HOME-05`.

## Tickets

`P7-PRIVACY-02` and `P7-PRIVACY-03` (this pass). The remaining Profile screen is most likely `P7-HOME-05` per `docs/02-task-breakdown.md`.
