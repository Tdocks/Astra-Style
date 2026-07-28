//
//  AppStoreTransactionPayload.swift
//  AstraStyle
//
//  What the client forwards to `POST /subscriptions/sync` (spec §14) after
//  verifying a StoreKit 2 transaction locally via `Transaction.currentEntitlements`.
//  The server is the source of truth for entitlement (spec §16
//  "server-side subscription reconciliation") — this payload lets it
//  correlate a device-observed transaction with its own App Store Server
//  Notifications feed.
//

import Foundation

public struct AppStoreTransactionPayload: Encodable, Sendable {
    public var originalTransactionID: String
    public var transactionID: String
    public var productID: String
    public var purchaseDate: Date
    public var expiresDate: Date?
    public var environment: SubscriptionEnvironment

    public init(
        originalTransactionID: String,
        transactionID: String,
        productID: String,
        purchaseDate: Date,
        expiresDate: Date? = nil,
        environment: SubscriptionEnvironment
    ) {
        self.originalTransactionID = originalTransactionID
        self.transactionID = transactionID
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.expiresDate = expiresDate
        self.environment = environment
    }

    enum CodingKeys: String, CodingKey {
        case originalTransactionID = "original_transaction_id"
        case transactionID = "transaction_id"
        case productID = "product_id"
        case purchaseDate = "purchase_date"
        case expiresDate = "expires_date"
        case environment
    }
}
