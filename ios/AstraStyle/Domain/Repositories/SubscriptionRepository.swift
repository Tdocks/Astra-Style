//
//  SubscriptionRepository.swift
//  AstraStyle
//
//  Owns `subscriptions` (spec §9) and StoreKit 2 <-> server reconciliation
//  (spec §16, §14 `subscriptions/sync`).
//

import Foundation

public protocol SubscriptionRepository: Sendable {
    func fetchCurrentSubscription() async throws -> Subscription

    /// Forwards a locally-verified StoreKit 2 transaction to the server so
    /// it can be reconciled against App Store Server Notifications
    /// (spec §16 "server-side subscription reconciliation").
    /// Calls `POST /subscriptions/sync`.
    func syncTransaction(_ payload: AppStoreTransactionPayload) async throws -> Subscription

    /// Re-syncs all current entitlements after "Restore Purchases"
    /// (spec §16 "Paywall" action list).
    func restorePurchases() async throws -> Subscription
}
