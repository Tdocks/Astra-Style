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

    @Test(
        "Non-entitled statuses correctly report no access",
        arguments: [SubscriptionStatus.inBillingRetry, .expired, .revoked, .none]
    )
    func nonEntitledStatusesAreNotEntitled(status: SubscriptionStatus) {
        let subscription = Subscription(userID: UUID(), status: status)
        #expect(!subscription.isEntitledToPremium)
    }
}
