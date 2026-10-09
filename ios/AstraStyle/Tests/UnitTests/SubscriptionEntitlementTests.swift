//
//  SubscriptionEntitlementTests.swift
//  AstraStyleTests
//
//  Spec §22 "Unit tests: Subscription entitlement logic".
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Subscription entitlement")
struct SubscriptionEntitlementTests {

    @Test("Active status is entitled to premium")
    func activeIsEntitled() {
        let subscription = Subscription(userID: UUID(), status: .active)
        #expect(subscription.isEntitledToPremium)
    }

    @Test("Grace period is still entitled, so a billing hiccup doesn't immediately lock the user out")
    func gracePeriodIsEntitled() {
        let subscription = Subscription(userID: UUID(), status: .inGracePeriod)
        #expect(subscription.isEntitledToPremium)
    }

    @Test("Billing retry is not entitled even before its expiry")
    func billingRetryIsNotEntitled() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let subscription = Subscription(
            userID: UUID(),
            status: .inBillingRetry,
            expiresAt: now.addingTimeInterval(60)
        )
        #expect(!subscription.isEntitledToPremium(at: now))
        #expect(!subscription.isEntitledToPremium(at: now.addingTimeInterval(60)))
    }

    @Test("Active status does not grant Premium after the server expiry")
    func activeStatusExpiresMidSession() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let subscription = Subscription(
            userID: UUID(),
            status: .active,
            expiresAt: now.addingTimeInterval(60)
        )
        #expect(subscription.isEntitledToPremium(at: now))
        #expect(!subscription.isEntitledToPremium(at: now.addingTimeInterval(60)))
        #expect(!subscription.isEntitledToPremium(at: now.addingTimeInterval(120)))
    }

    /// `trialing` is a real member of the Postgres `subscription_status` type
    /// and was missing from the Swift enum entirely. A user mid-trial is
    /// paying-equivalent and must have full access; treating them as
    /// non-entitled would lock them out of the thing they are trialling.
    @Test("A user in their trial period is entitled")
    func trialingIsEntitled() {
        let subscription = Subscription(userID: UUID(), status: .trialing)
        #expect(subscription.isEntitledToPremium)
    }

    @Test(
        "Non-entitled statuses correctly report no access",
        arguments: [
            SubscriptionStatus.expired,
            .revoked,
            .cancelled,
            .inBillingRetry
        ]
    )
    func nonEntitledStatusesAreNotEntitled(status: SubscriptionStatus) {
        let subscription = Subscription(userID: UUID(), status: status)
        #expect(!subscription.isEntitledToPremium)
    }
}
