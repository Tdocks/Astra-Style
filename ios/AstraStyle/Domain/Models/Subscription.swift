//
//  Subscription.swift
//  AstraStyle
//
//  Maps `subscriptions` (spec §9). Reconciled server-side against App
//  Store server notifications; the client only ever reads this via
//  `SubscriptionRepository` and never trusts local StoreKit transaction
//  state alone for entitlement decisions (spec §16 "server-side
//  subscription reconciliation").
//

import Foundation

public struct Subscription: Codable, Hashable, Sendable {
    public var userID: UUID
    public var appStoreOriginalTransactionID: String?
    public var productID: String?
    public var status: SubscriptionStatus
    public var expiresAt: Date?
    public var environment: SubscriptionEnvironment

    public init(
        userID: UUID,
        appStoreOriginalTransactionID: String? = nil,
        productID: String? = nil,
        status: SubscriptionStatus = .none,
        expiresAt: Date? = nil,
        environment: SubscriptionEnvironment = .production
    ) {
        self.userID = userID
        self.appStoreOriginalTransactionID = appStoreOriginalTransactionID
        self.productID = productID
        self.status = status
        self.expiresAt = expiresAt
        self.environment = environment
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case appStoreOriginalTransactionID = "app_store_original_transaction_id"
        case productID = "product_id"
        case status
        case expiresAt = "expires_at"
        case environment
    }

    /// Entitlement check used to gate premium features (spec §16). Treats
    /// grace period as still-entitled, matching common StoreKit guidance so
    /// a billing hiccup doesn't immediately lock the user out.
    public var isEntitledToPremium: Bool {
        switch status {
        case .active, .inGracePeriod: true
        case .inBillingRetry, .expired, .revoked, .none: false
        }
    }
}

/// Product identifiers for the two premium plans (spec §16 pricing).
public enum AstraProductID: String, CaseIterable, Sendable {
    case monthly = "com.astrastyle.app.premium.monthly"
    case annual = "com.astrastyle.app.premium.annual"
}
