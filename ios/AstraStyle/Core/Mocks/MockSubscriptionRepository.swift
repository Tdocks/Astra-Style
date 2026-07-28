//
//  MockSubscriptionRepository.swift
//  AstraStyle
//
//  In-memory `SubscriptionRepository` for previews/tests (spec §31).
//

import Foundation

public actor MockSubscriptionRepository: SubscriptionRepository {
    private var subscription: Subscription

    public init(status: SubscriptionStatus = .active) {
        subscription = Subscription(
            userID: SampleData.userID,
            appStoreOriginalTransactionID: "preview-original-transaction",
            productID: AstraProductID.annual.rawValue,
            status: status,
            expiresAt: Calendar.current.date(byAdding: .year, value: 1, to: .now),
            environment: .sandbox
        )
    }

    public func fetchCurrentSubscription() async throws -> Subscription { subscription }

    public func syncTransaction(_ payload: AppStoreTransactionPayload) async throws -> Subscription {
        subscription = Subscription(
            userID: SampleData.userID,
            appStoreOriginalTransactionID: payload.originalTransactionID,
            productID: payload.productID,
            status: .active,
            expiresAt: payload.expiresDate,
            environment: payload.environment
        )
        return subscription
    }

    public func restorePurchases() async throws -> Subscription { subscription }
}
