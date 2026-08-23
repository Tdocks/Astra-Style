# 0018. Guest trial path may return (0014-bis)

## Status

Accepted (2026-08-23). **Amends [0014](0014-account-required-no-guest-mode.md)**
for later waves. Does **not** restore guest code in this change.

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

1. **0014 stays in force until a later wave lands guest code.** Authentication
   is still required on Welcome. `P1-AUTH-04` / `P1-AUTH-05` stay
   **Withdrawn** under 0014 until that wave ships.
2. **When guest is rebuilt**, it is a new trial path, not a revert of
   `GuestClosetRepository`. Guest photo bytes still must not reach
   `user-content` (0011’s Storage rule). Migration must include onboarding
   profile rows, not only closet items.
3. **A feature flag over dead guest branches is still forbidden.** Restore
   is a dedicated wave with tests, not uncommented wrappers.

## Consequences

- Wave 5 of the still-out program is the implementation slice.
- App Store 5.1.1(v) remains the review question if guest never returns;
  if it does, the trial path is the answer.
- Sign in with Apple first on Welcome is unchanged until Wave 5.
