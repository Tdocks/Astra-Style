# Atomic Daily Brief and product trials — implementation acceptance

## Scope and unchanged behavior

This pass closes the two known count-before-write gaps recorded in the
subscription-limits acceptance. It does not add new product tickets or change
Free/Premium allowance amounts. Daily Brief has three lifetime brief-date
successes; product verdict has one lifetime successful evaluation. Cached briefs
remain readable at the limit. Empty-closet briefs are valid persisted results.
Explicit regeneration is blocked once the three-date allowance is exhausted;
measured weather/schedule refresh remains exempt. Product extraction checks
allowance but does not consume it. No automatic upgrade prompt is introduced.

## Verified behavior

- Atomic owner admission and persistence cannot exceed the lifetime limits under
  simultaneous requests; failed writes leave no usage or partial outfit set.
- Same-date first requests converge on one stored brief and outfit set.
- Same request ID replays the same persisted response without another debit;
  changed payloads are rejected, including product retries at exhausted allowance.
- Deleting individual brief/evaluation rows does not refund lifetime usage;
  retries of a removed source return 404 instead of resurfacing its content.
  Deleting the account removes all owner usage and operation records.
- Entitled Premium bypasses limits; expiry reverts to the existing Free behavior.
- Client table/RPC permissions cannot bypass the server admission path.
- Full backend format/lint/type checks and 1,079 tests passed. Fresh migration/RLS
  groups 1–57 passed. Four parallel database requests admitted exactly three
  Daily Briefs and one product verdict, with ledger counts matching persistence.
- `20261009213641_atomic_morning_loop_trial_admission.sql` is applied to production.
  Daily Brief v19 and products v19 are ACTIVE with JWT verification enabled.

## Hosted harness

`supabase/functions/daily-brief/hosted_morning_loop_acceptance.ts` uses one
synthetic anonymous owner, three synthetic closet pieces and read-only existing
catalog candidates. It makes no extraction, styling-provider or image calls.
Normal account deletion runs in finally, and independent SQL must confirm cleanup.
The hosted harness passed against production: simultaneous same-date briefs
converged on the same stored response without duplicate outfit sets; distinct
brief dates were limited to three; cache reads and measured schedule refresh were
allowed at the cap. Product evaluation admitted one of two simultaneous candidates,
replayed the full original response, and rejected changed request payloads. Both
features retained usage after source DELETE and returned 404 for deleted-result
replay. Direct client writes and private-ledger reads returned 403.

Owner: `e83abdd0-60b3-49dc-89ea-93b0f07d7729`.
Normal account deletion: HTTP 202, receipt `c5a36998-1a5a-4bc2-b995-80d99412ee13`.
Independent SQL confirmed zero Auth, closet, outfits/items, briefs, evaluations,
usage and operation rows for that owner. The shared catalog was not modified.

Live privilege checks confirm the three new RPCs are SECURITY INVOKER,
service-role executable, and denied to authenticated callers. Security advisors
retain the existing 35 warnings; no-policy INFO notices increased from 16 to 18
for two deliberately private RLS ledgers. This is not a clean advisor scan; see
[Supabase RLS advisor guidance](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).
Schema/column checks and the 179-ticket progress checker pass. Tracker totals stay
125 Done, 49 Partial and 5 Not started; this corrects known reliability gaps in
existing tickets rather than claiming new feature completion.

## Remaining separate limitations

Old outfit sets replaced by deliberate regeneration remain active/unreferenced
under the existing documented policy; this pass prevents new cold-request race
orphans without deleting a user's saved or worn looks. Real-device weather,
calendar permissions and signed StoreKit lifecycle acceptance remain separate.
Internal operation records retain replay payloads until account deletion; this
pass prevents returning a payload whose source was removed, and does not claim
a per-record payload purge. No native source changes or new TestFlight build
belong to this pass.
