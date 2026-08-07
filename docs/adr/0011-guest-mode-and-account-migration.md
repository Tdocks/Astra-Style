# 0011. Guest mode and account migration

## Status

**Superseded by [0014](0014-account-required-no-guest-mode.md) (2026-08-06).**
Guest mode is removed and an account is required before onboarding. This
document is kept as the record of why guest mode was built the way it was —
in particular its Consequences section, which predicted the profile-migration
data loss that then shipped, and its Alternatives, where Supabase anonymous
auth is the option to revisit if a trial path is ever wanted again.

Originally: Accepted

## Context

§6.2 (Welcome/authentication) offers "Explore demo" alongside Sign in with Apple and
email, with explicit guest-mode restrictions: local closet capped at 10 items, no
cloud sync, one Style Studio sample, no shopping history. §7 lists "Guest migration
to account" as a required functional capability. This implies a user can add real
data (closet scans, at minimum) before ever creating an account, and that data must
survive the transition to a real account without being lost and without creating a
security hole (e.g., one guest's local data leaking into another user's account on
the same device, or a migration path that bypasses RLS).

## Decision

1. **Guest mode is fully local, with no server-side identity at all** until
   migration. Guest data (up to 10 closet items, their images, and the one Style
   Studio sample) lives only in SwiftData and local file storage on-device — never
   uploaded to Supabase Storage or written to any Supabase table under a placeholder
   `user_id`. This means there is no server-side guest record to secure or clean up,
   and no possibility of guest data being associated with the wrong account through
   a server-side bug.
2. **Migration is a one-time, explicit, user-initiated upload step triggered
   immediately after the user completes Sign in with Apple or email auth from
   within an existing guest session** (not a background sync). The flow:
   - The freshly authenticated session's `user_id` becomes available.
   - The app uploads each locally-stored guest closet item image to
     `users/{user_id}/closet/...` (ADR 0010's path convention) and inserts the
     corresponding `closet_items`/`closet_item_images` rows via the authenticated
     client, which RLS enforces are owned by the new `user_id` — there is no
     privileged bypass path.
   - The one guest Style Studio sample, if the user chooses to keep it, migrates the
     same way into `users/{user_id}/studio/...`.
   - On confirmed upload success for every item, local guest data is cleared from
     SwiftData; on partial failure, guest data is retained locally and the migration
     is resumable/retryable rather than silently dropping unmigrated items.
3. **The 10-item guest cap is enforced client-side only during guest mode** and is
   irrelevant post-migration — a migrated user is immediately subject to normal
   Free/Premium tier limits (§16), not a guest-specific limit.
4. **No guest data is ever associated with a `user_id` before real authentication
   exists.** There is deliberately no "anonymous Supabase Auth user" pattern used
   here — guest mode does not create a shadow Supabase Auth identity that later gets
   "linked"; it creates no server-side identity at all until the user authenticates
   for real, at which point migration uploads under that real identity's RLS
   context.

## Consequences

### Positive

- No server-side guest identity means no server-side guest data to secure, rate
  limit, or garbage-collect if a guest abandons the app — the entire guest-mode
  security surface is "protect the local device," which is a much smaller problem
  than "protect a server-side anonymous account and safely link it later."
- Because migration happens over the *authenticated* client using ordinary RLS-
  governed inserts, there is no special-case, elevated-privilege "adopt this
  anonymous user's data" server function to write and audit — the same insert path
  a normal authenticated closet-scan upload uses is the same path migration uses,
  which minimizes new attack surface.
- User-initiated, foreground migration with explicit success/failure per item gives
  the user a visible, resumable path if migration is interrupted (app backgrounded,
  network drop mid-upload) rather than a silent background sync that could partially
  fail unnoticed.
- Clearing local guest data only after confirmed server success means a failed or
  interrupted migration cannot lose data — the worst case is "still guest, retry
  available," never "guest data silently deleted before it was safely uploaded."

### Negative (real costs, named)

- **Guest data is fully at the mercy of the device until migration.** If the user
  deletes the app, loses the device, or the device's local storage is corrupted
  before ever creating an account, guest-mode closet items are unrecoverable — there
  is no server-side backup for guest data by design. This is a real, user-facing
  data-loss risk that must be communicated in-product (a clear "sign in to save your
  closet permanently" nudge), not just accepted silently.
- **The anonymous-Supabase-Auth-user pattern that was explicitly avoided here is a
  well-trodden, officially-supported Supabase pattern** (anonymous sign-in, later
  `updateUser`/identity-linking to convert to a permanent account) — by not using
  it, the team takes on hand-building the local-storage-then-upload migration flow
  instead of leaning on a first-party Supabase primitive, which is more code to
  write and test, in exchange for the smaller-attack-surface property above. This is
  a deliberate trade, not a free win.
- Foreground, user-initiated migration means the user experiences a visible
  "uploading your closet..." wait immediately after authenticating, which is a
  worse first-run experience than a silent background migration, especially for a
  user who added the full 10 guest items with images on a slow connection — this
  needs a well-designed progress state (§21 requires loading/error/retry states for
  every feature) or it will feel broken.
- If a device is shared (unlikely but not impossible — e.g., a demo device in a
  retail context) and guest mode is used by multiple people before any of them
  authenticate, there is no per-person isolation of guest data on that device — the
  10-item guest closet is a single local pool, not multi-guest-aware. This is an
  accepted limitation for a personal styling app (single-user-per-device is the
  overwhelmingly common case) but should be stated explicitly rather than
  discovered later.
- Every field captured in guest mode (measurements entered during onboarding if the
  user reaches onboarding before authenticating, style quiz answers, etc.) needs the
  same migrate-on-auth treatment as closet items, which broadens the migration
  surface beyond just images/closet rows — profile, style, and body data (§9's
  `style_profiles`, `body_profiles`, `lifestyle_profiles`) must also be captured
  locally during guest onboarding and migrated, not just closet scans, or a user who
  completes onboarding as a guest and then signs in loses their onboarding answers.

## Alternatives Considered

- **Supabase anonymous auth (`signInAnonymously`) with later identity linking.**
  A legitimate, officially-supported alternative that would let guest data live in
  real Supabase tables/Storage under RLS from the start, with migration reduced to
  an identity-linking API call rather than a manual re-upload. Rejected for v1
  specifically because it creates a server-side identity (and therefore server-side
  data, cost, and cleanup burden) for every guest, including the large fraction who
  never convert, and because §6.2's guest restrictions (no cloud sync, explicitly)
  read as intentionally scoping guest mode to local-only. Worth revisiting if guest
  abandonment/data-loss complaints (above) prove more costly than the added
  server-side guest footprint would have been.
- **No guest mode at all; require authentication before any closet interaction.**
  Rejected: contradicts §6.2's explicit "Explore demo" flow and §7's explicit
  requirement for guest migration, and removes a meaningful low-friction trial path
  for a premium app that benefits from letting a skeptical user try scanning before
  committing to an account.
- **Silent background migration immediately on auth, with no visible progress
  state.** Rejected: for up to 10 images this may be fast, but on a poor connection
  a silent background upload that the user navigates away from mid-flight risks a
  confusing partial-migration state with no user-visible explanation, which is worse
  than a short, honest, visible progress indicator.
