# 0018. Guest trial path may return (0014-bis)

## Status

Accepted (2026-08-23). **Amends [0014](0014-account-required-no-guest-mode.md).**
**Amended again (2026-08-23, Wave 5):** guest trial code is in the tree.
Welcome `welcome.tryWithoutAccount` calls `signInAnonymously()`. Guest photos
stay in `GuestLocalImageStore` until Apple/email link, then
`migrateGuestLocalImages` uploads them. Closet cap is 10 (`GuestLimits`).
Hosted GoTrue Anonymous is on for `anutsdzbxycaavmmkewo` (empty-body
`/auth/v1/signup` returns `is_anonymous: true`). Manual identity linking
(`security_manual_linking_enabled`) is on so Apple/email link can keep the
same `user_id`. If signup ever returns `anonymous_provider_disabled` again,
Welcome maps it to an honest sentence instead of a generic retry.

## Context

The still-out program GO’d the entire leftover list, including guest.
0014 deleted guest because the trial path was unreachable (no scan),
cost four bugs, and never migrated profile rows. Those facts remain true.
A gender-toggle-shaped “Explore demo” on Welcome would re-litigate 0014
badly.

If guest returns, it must not be the deleted subsystem. 0014’s own
alternative still stands: Supabase anonymous auth, or an on-device-only
scan with a local image store and a real migration of closet **and**
profile tables.

## Decision

1. **Wave 5 restored a trial path.** Welcome offers Apple, email, and
   “Try without an account.” `P1-AUTH-04` / `P1-AUTH-05` are **Done**.
2. **This is a new trial path, not a revert of `GuestClosetRepository`.**
   Guest photo bytes still must not reach `user-content` (0011’s Storage
   rule) until Apple/email link. Migration includes closet rows (and the
   same `user_id` for onboarding profile).
3. **A feature flag over dead guest branches is still forbidden.**

## Consequences

- Wave 5 of the still-out program landed the implementation slice.
- App Store 5.1.1(v) is answered by the trial path once hosted Anonymous
  is on; until then, Apple/email remain the working doors.
- Sign in with Apple stays first on Welcome; guest is the third CTA.
