# ADR 0048: Deliver StoreKit transactions before finishing them

Status: Accepted — 2026-10-12

StoreKit purchases were finished before the backend acknowledged them, and the app had no transaction-update listener. A dropped sync response or approval after the paywall closed could therefore leave a paid user without activated access.

Retain the verified payload during paywall sync failures and expose an activation retry, disabling further purchases while delivery is pending. Finish a transaction only after backend reconciliation succeeds. Read verified unfinished transactions at launch/account changes/reconnect and observe Transaction.updates for delayed approval and renewal. Automatic delivery requires a supported Astra product, an appAccountToken matching the signed-in owner, and a returned subscription belonging to that same owner. Account changes or network failures leave the transaction unfinished. Legacy purchases without an appAccountToken use explicit Restore; they are never automatically assigned to a different account.

The backend remains entitlement truth. Native restore ignores revoked, upgraded and expired transactions and reconciles all verified receipts chronologically. Inactive backend results cannot dismiss the paywall as a successful activation.

The same account-scoped observer coalesces overlapping unfinished/update delivery. Its app task follows the active session lifetime; mock and local Supabase QA modes do not invoke hosted subscription sync. Tests use the live StoreKit adapter with a locally configured StoreKit engine and an injected no-op account-authentication sync. Production keeps AppStore.sync; local signed receipts are never sent to hosted Supabase.

SDK limitation: on this Xcode 27/iOS 27 simulator, forced expiry changed SKTestTransaction.expirationDate while Transaction.currentEntitlements and Product.SubscriptionInfo.status still reported a future subscribed receipt. The failed probes are retained as acceptance evidence; no production rule is weakened or ticket closed on that result.
