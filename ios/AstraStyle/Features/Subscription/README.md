# Subscription

Owns StoreKit 2 integration and the paywall (spec §16).

## Status

**Paywall at the 30-item cap.** Purchase and restore sync `original_transaction_id` to
`POST /subscriptions/sync`. Wear This and paste-evaluate are not behind this door.
Legal URLs stay omitted while unpublished.

## What this module owns

- The paywall: marble hero, benefit list, monthly ($12.99) and annual ($79.99) plans, restore purchases, manage subscription, legal links.
- StoreKit 2 purchase flow and transaction verification (`Transaction.currentEntitlements`), forwarded to the server for reconciliation.
- Free-tier limit enforcement surfaces (closet cap, outfit generation limits, Kyra daily conversation cap, Style Studio trial) — the limits themselves are enforced server-side, but this module owns the client-side "you've hit your limit, here's the paywall" prompts, wired through `AppRouter.presentModal(.paywall(context:))`.

## Governing spec sections

§16 (subscription model, pricing, paywall requirements), §9 (`subscriptions`), §14 (`POST /subscriptions/sync`), §18 (`paywall_viewed`, `subscription_started/renewed/cancelled`), §23 (StoreKit subscription is a "must ship"), §30 (Definition of Done item 12: subscribe and restore purchase).

## What already exists to build against

- `Domain/Repositories/SubscriptionRepository.swift` — `syncTransaction(_:)`, `restorePurchases()`.
- `Domain/Models/Subscription.swift` — `isEntitledToPremium` (treats grace period as still-entitled), `AstraProductID` (the two product identifiers).
- `Domain/Models/AppStoreTransactionPayload.swift` — what gets forwarded to the server after local StoreKit verification.
- `App/AppRouter.swift` — `PaywallContext` (`Domain/Models/PaywallContext.swift`) already enumerates every trigger point this module needs to handle.
- `Core/Mocks/MockSubscriptionRepository.swift`.

## Tickets

Filled in by the **P7-SUB** tickets in `docs/02-task-breakdown.md`.
