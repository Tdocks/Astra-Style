# Subscription limits — implementation acceptance

## Scope

P7-SUB-04: consistent subscription status and expiry, active closet limits,
Kyra new-conversation limits, outfit generation limits, and Studio allowances.
P7-SUB-04 and P7-TEST-01 are complete for their implementation acceptance criteria.
No TestFlight upload or version increment belongs to this pass.

## Policy

- Premium: trialing, active, or in_grace_period; a non-null expiry must be strictly
  in the future. Billing retry does not grant Premium. A verified Apple grace
  deadline is retained rather than the expired paid-period deadline.
- Closet: 10 active items for anonymous guests, 30 for signed-in Free users,
  unlimited for entitled Premium. Existing items remain editable after expiry.
  Restores and direct API inserts obey the same server cap.
- Outfit generation: a configurable provisional default of five successful
  generation requests per UTC day. The master spec specifies limited generation
  without a numeric allowance; five is an implementation setting, not a separately
  confirmed product requirement. Failed or empty requests release their slot.
  Direct generation and Kyra create_outfit share this allowance; Premium bypasses it.
- Kyra: three new conversations per UTC day for Free; continuing a thread is
  separate from starting one. Outfit tools inside existing threads still check
  the generation allowance. A durable start ledger prevents deletion refunds;
  transactional admission prevents simultaneous starts from exceeding the cap.
  Request-ID retries reuse thread admission without another allowance charge;
  changed prompts or removed original threads fail without creating replacements.
- Studio: one lifetime standard-image trial for Free, a configured monthly
  allowance for Premium. A Premium monthly limit shows its reset, not an upgrade.
- Existing Daily Brief and paste-evaluation trial counts stay unchanged. Their
  lifetime limits have no daily reset and remain inline per ADR 0017.
- Wear This stays free. Traffic throttling is distinct from subscription limits.

## Verification gates

Final native focused acceptance passed 90 selected tests, including the outfit
quota simulator UI test; xcresult reports 90 passed and zero failures. It covers same-wrapper guest-to-Free and Premium-to-Free
transitions, subscription expiry, typed quota versus traffic errors, closet cap
rejection without offline queueing, and builder preservation/manual save/upgrade.
Result: `/tmp/astra-inspiration-build/Logs/Test/Test-AstraStyle-2026.10.09_13-43-25--0400.xcresult`.
Focused Kyra handler/tool checks passed 40 tests after the atomic persistence,
conversation admission, and retry changes.

Final verification passed:

- Deno format, lint and type checks; 1,076 backend tests.
- Fresh PostgreSQL 18 scratch migration run and SQL test groups 1–56.
- Twelve simultaneous requests admitted exactly five outfit reservations, one
  closet insert at 29 active items, and three Free Kyra conversation starts.
- Strict SwiftLint, schema/column checks, progress consistency and diff checks.
- Production migrations `20261009175509_outfit_generation_quota.sql` and
  `20261009175515_kyra_atomic_outfit_generation.sql` applied successfully.
- Seven functions deployed ACTIVE: outfits v21, Kyra v26, Studio v26,
  Daily Brief v18, products v18, subscriptions v9, App Store v5. JWT verification
  remains enabled except the intentionally signed-payload App Store endpoint.

## Hosted acceptance

`supabase/functions/outfits/hosted_entitlement_limits_acceptance.ts` ran once
against production with one disposable anonymous owner and no provider/image calls.
It proved ten active items, denial of the eleventh and over-cap restore, archive
freeing one slot, five nonempty outfit-generation successes, a typed sixth-request
limit with UTC reset, unchanged request replay, and rejection of changed payloads.
An exhausted builder request stopped before thread creation. Direct client ledger
reads, quota RPC calls and Kyra thread insertion returned 403.

Synthetic owner: `42df7434-c72b-4c05-bd95-3cbf3dbcccbc`.
Normal account deletion returned 202, receipt `40584896-d169-4a0f-8e27-a0f0134e7de1`.
Independent SQL confirmed zero Auth, closet, generation-usage/reservation,
outfit-operation, conversation-usage and thread-operation rows for that owner.

Live inspection confirms all four new RPCs are SECURITY INVOKER, executable by
service_role and not authenticated. Security advisors retain 35 existing warnings;
INFO notices increased from 10 to 16 because six server-only RLS tables have no
client policies. This is not a clean advisor scan. See
[Supabase RLS advisor guidance](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

Existing Daily Brief and product-evaluation lifetime trial admission remains a
count-before-write flow, so simultaneous requests may exceed those legacy trial
counts. This pass does not claim concurrency enforcement for those two allowances.

The SQL fixture uses test-only SELECT grants to prove RLS isolation; production
client table privileges and RPC denial require independent hosted verification.

## Remaining outside this pass

Live signed Apple notification and physical-device sandbox purchase, renewal,
cancellation, and restore acceptance remain separate release gates. Build 32 does
not include this pass or the later Monthly Review corrections.

## Follow-up: lifetime trial races resolved

The later [atomic morning-loop acceptance](2026-10-09-morning-loop-atomic-acceptance.md)
records deployed fixes for the Daily Brief and product-evaluation concurrency,
delete-refund and replay gaps identified above. The original evidence remains
historical; current admission is transactional. Regeneration retains its existing
distinct-date accounting, and replay payload retention is documented separately.
