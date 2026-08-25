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

    @Test("Legal links are shown once the documents are published")
    func showsLegalWhenPublished() {
        let model = PaywallViewModel(
            context: .closetLimit,
            purchasing: MockStoreKitPurchasing(),
            subscriptionRepository: MockSubscriptionRepository(status: .expired)
        )
        #expect(AstraLegal.isPublished == true)
        #expect(model.showsLegalLinks == true)
    }

    @Test("Kyra and Studio copy names the cap; Wear This stays out of the charge")
    func contextCopy() {
        let kyra = PaywallViewModel(
            context: .kyraDailyLimit,
            purchasing: MockStoreKitPurchasing(),
            subscriptionRepository: MockSubscriptionRepository(status: .expired)
        )
        #expect(kyra.subhead.contains("Three conversations"))
        #expect(!kyra.subhead.contains("Wear This stays free"))
        let studio = PaywallViewModel(
            context: .studioQuota,
            purchasing: MockStoreKitPurchasing(),
            subscriptionRepository: MockSubscriptionRepository(status: .expired)
        )
        #expect(studio.subhead.contains("visual estimate"))
        #expect(!studio.subhead.contains("Wear This stays free"))
        let brief = PaywallViewModel(
            context: .dailyBrief,
            purchasing: MockStoreKitPurchasing(),
            subscriptionRepository: MockSubscriptionRepository(status: .expired)
        )
        #expect(brief.subhead.contains("Daily Brief"))
        let paste = PaywallViewModel(
            context: .pasteEvaluate,
            purchasing: MockStoreKitPurchasing(),
            subscriptionRepository: MockSubscriptionRepository(status: .expired)
        )
        #expect(paste.subhead.contains("product verdict"))
    }
}
