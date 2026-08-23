//
//  PaywallViewModelTests.swift
//  AstraStyleTests
//
//  Closet-cap paywall: purchase syncs a transaction; restore with nothing
//  stays ready; legal links stay off while unpublished. Wear This is not
//  in this type.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Paywall at the closet cap")
@MainActor
struct PaywallViewModelTests {

    @Test("Offerings load, then a purchase syncs and succeeds")
    func purchaseSyncsTransaction() async {
        let purchasing = MockStoreKitPurchasing()
        let subscriptions = MockSubscriptionRepository(status: .expired)
        let model = PaywallViewModel(
            context: .closetLimit,
            purchasing: purchasing,
            subscriptionRepository: subscriptions
        )
        await model.onAppear()
        #expect(model.offerings.count == 2)
        await model.purchase(.monthly)
        #expect(model.state == .succeeded)
        #expect(model.subscription?.isEntitledToPremium == true)
    }

    @Test("User cancel leaves the paywall ready, not entitled")
    func cancelledPurchaseStaysReady() async {
        var purchasing = MockStoreKitPurchasing()
        purchasing.purchasePayload = nil
        let model = PaywallViewModel(
            context: .closetLimit,
            purchasing: purchasing,
            subscriptionRepository: MockSubscriptionRepository(status: .expired)
        )
        await model.onAppear()
        await model.purchase(.annual)
        #expect(model.state == .ready)
        #expect(model.subscription == nil)
    }

    @Test("Legal links are omitted while documents are unpublished")
    func omitsLegalWhileUnpublished() {
        let model = PaywallViewModel(
            context: .closetLimit,
            purchasing: MockStoreKitPurchasing(),
            subscriptionRepository: MockSubscriptionRepository(status: .expired)
        )
        #expect(AstraLegal.isPublished == false)
        #expect(model.showsLegalLinks == false)
    }
}
