# Recurring reminder scheduling recovery — 2026-10-18

## Fix

Recurring daily, monthly and closet-care scheduling previously discarded iOS
scheduling errors after persisting preferences. Errors now reach the caller;
preferences are committed after scheduling succeeds. On failure, restoration of
the previous recurring schedule is attempted. Notification Settings reports time
update failures and disables controls while an update is pending.

A small notification-center adapter allows deterministic failure tests without
requesting OS permission. The production adapter still uses UserNotifications.

## Verification

- Existing iPhone 18 Pro / iOS 27.0 simulator; canonical `ios/build/DerivedData`.
- **10 passed, 0 failed, 0 skipped**: LiveReminderServiceTests and HomeWeekStripTests.
- Includes rejected opt-in/retry, rejected time change with prior schedule
  restoration, denied permission, and existing packing/week-strip regressions.
- Strict lint passed for all four changed Swift files; diff whitespace check passed.
- Result bundle: `/tmp/astra-reminders-20261018.xcresult`.

Actual OS notification delivery remains unverified. Calendar and packing background
scheduling still use best-effort submission; this pass does not claim their error
reporting or delivery is complete. Restoration can also fail if iOS continues
rejecting requests. No phone interaction, deployment or TestFlight upload occurred.
