# 0009. StoreKit 2 with server-side reconciliation over RevenueCat

## Status

Accepted

## Context

§16 specifies a Free tier and an "Astra Style Premium" subscription
($12.99/month, $79.99/year) gating closet size, Daily Brief depth, Wardrobe Graph
features, product verdicts, packing, monthly reviews, Style Studio quota, and Kyra
memory depth. §16 states: "Use StoreKit 2 and server-side subscription
reconciliation." §9 defines a `subscriptions` table
(`app_store_original_transaction_id`, `product_id`, `status`, `expires_at`,
`environment`) implying entitlement state is mirrored into Supabase. §14 lists
`POST /subscriptions/sync` and `POST /app-store/webhook` Edge Function endpoints.

The two realistic implementation paths are: (a) StoreKit 2 directly, with the app
verifying transactions via `Transaction.currentEntitlements`/`Transaction.updates`
and an Edge Function independently verifying and reconciling entitlement via
App Store Server Notifications V2 and the App Store Server API; or (b) a
subscription-infrastructure platform such as RevenueCat sitting between StoreKit and
the backend, handling receipt validation, entitlement caching, and webhook
normalization.

## Decision

Use StoreKit 2 directly from the iOS client for the purchase/restore UX, with
Supabase Edge Functions as the source of truth for entitlement state: the app
reports transactions to `POST /subscriptions/sync`, and `POST /app-store/webhook`
consumes App Store Server Notifications V2 server-to-server so that entitlement
state in the `subscriptions` table stays correct even when the app isn't running
(renewals, cancellations, billing-issue holds, refunds). The app treats its own
local `Transaction.currentEntitlements` check as a fast-path/offline convenience,
not as the authoritative gate for Premium features — the server-reconciled record is
authoritative for anything that matters (e.g., unlocking a Studio generation quota
that costs Astra real inference money).

## Consequences

### Positive

- No additional subscription-infrastructure vendor, no additional per-transaction
  fee beyond Apple's own cut — RevenueCat's free tier caps out and its paid tiers
  take an additional percentage/flat fee on top of Apple's, which directly erodes
  margin on an already thin $12.99/month price point (see the cost-risk arithmetic in
  `docs/11-risk-register.md`).
- One fewer third party sitting in the data path between the app and Apple's own
  entitlement system — server logic sees exactly the App Store Server Notification
  payloads and StoreKit transaction data Apple sends, with no intermediate vendor
  transformation to account for when debugging an entitlement discrepancy.
- StoreKit 2's `Transaction.updates` async sequence and
  `Transaction.currentEntitlements` are a clean fit for this app's structured
  concurrency approach (ADR 0006) with no SDK-specific reactive pattern to bridge.
- Full control over the reconciliation logic in `POST /app-store/webhook` means
  edge cases specific to this business (e.g., how a billing-grace-period user's
  Premium features degrade, exactly which features "Premium" gates per §16) are
  implemented exactly as specified, not through a third-party entitlement model that
  may not map cleanly onto Astra's specific tier structure.

### Negative (real costs, named)

- **This is real, non-trivial engineering work that RevenueCat exists specifically
  to remove.** Correctly handling App Store Server Notifications V2 (subscription
  renewals, grace periods, billing retry, price-increase consent, refunds,
  family sharing, upgrade/downgrade/crossgrade proration, revocation) is a long tail
  of edge cases that a mature third-party platform has already hardened against
  years of production traffic across many apps. Building and maintaining this
  in-house means Astra's team owns that hardening curve itself, and bugs here
  directly cost or lose revenue (a user who paid but isn't entitled; a user who
  cancelled but keeps access).
- No cross-platform entitlement unification "for free" — since ADR 0001 is iOS-only,
  this is not a cost today, but it means that if Android ever ships, subscription
  reconciliation logic (which RevenueCat would have unified) has to be built again
  for Google Play Billing from scratch, whereas RevenueCat customers get that
  unification largely for free.
- Testing StoreKit 2 flows requires StoreKit sandbox/Xcode configuration file
  discipline (§22 lists "StoreKit sandbox purchase" as a required integration test);
  RevenueCat's sandbox tooling and dashboard-based test-transaction visibility is
  generally considered more convenient than Apple's raw sandbox tooling for
  debugging a failed test purchase.
- Analytics/insights that RevenueCat provides out of the box (churn cohorts, trial
  conversion funnels, MRR dashboards across the subscriber base) must be built
  in-house on top of the `subscriptions` table and `analytics_events`, or paid for
  via a separate BI tool — this is a real, if secondary, cost of not adopting a
  platform whose product surface includes that reporting.

## What Would Justify Switching to RevenueCat

RevenueCat is a legitimate, widely-used choice, and this decision should be
revisited if any of the following becomes true:

- The team repeatedly ships entitlement bugs in production (users incorrectly
  gated or ungated) after the initial hardening period, indicating the in-house
  reconciliation logic is not converging on correctness fast enough relative to the
  cost of a platform that has already solved it.
- Android development is greenlit (reopening ADR 0001), at which point RevenueCat's
  cross-platform entitlement unification removes a second, independent
  App-Store/Play-Billing reconciliation implementation.
- The subscription model grows materially more complex (multiple concurrent
  entitlement products, promotional offers, win-back campaigns, complex trial
  structures) faster than the in-house reconciliation code can be safely extended,
  such that RevenueCat's pre-built support for these patterns would meaningfully
  reduce time-to-ship.
- A dedicated analytics/growth function needs RevenueCat's cohort and revenue
  dashboards and determines building equivalent in-house tooling costs more than
  RevenueCat's fee.

If none of these materialize, the in-house StoreKit 2 + server reconciliation path
remains the better economic choice at Astra's current scale and margin sensitivity.

## Alternatives Considered

- **RevenueCat.** Not rejected as illegitimate — see above — but not adopted for v1
  because of margin sensitivity at $12.99/month (see the cost risk arithmetic in
  `docs/11-risk-register.md`) and because the team judges the in-house
  reconciliation work tractable at MVP scale, per §16's explicit instruction to use
  StoreKit 2 with server-side reconciliation.
- **StoreKit 2 with no server reconciliation (trust `Transaction.currentEntitlements`
  on-device only).** Rejected: §16 explicitly requires server-side reconciliation,
  and trusting the device alone is straightforwardly spoofable/unreliable for
  gating server-cost features like Style Studio generation quota — a jailbroken or
  tampered client could claim entitlement it doesn't have.
- **Building on top of a generic payments platform (Stripe) instead of native
  App Store subscriptions.** Rejected outright: Apple requires In-App Purchase for
  digital subscription content consumed within the app, per App Store Review
  Guideline 3.1.1; a Stripe-only path would not pass App Store review for this
  product category.
