import Foundation
import Testing
@testable import AstraStyle

@Suite("Purchase delivery recovery")
@MainActor
struct PaywallRecoveryTests {
    @Test("A failed backend sync retries the paid transaction without another Apple purchase")
    func retryDoesNotPurchaseAgain() async {
        let purchasing = CountingPurchasing()
        let repository = RecoverySubscriptions(failures: 1)
        let model = PaywallViewModel(context: .settingsUpgrade, purchasing: purchasing,
                                     subscriptionRepository: repository)
        await model.onAppear()
        await model.purchase(.monthly)
        #expect(model.hasPendingPurchaseSync)
        #expect(model.subscription == nil)
        #expect(await purchasing.finishCount == 0)
        // Even tapping a different plan must recover the already paid purchase.
        await model.purchase(.annual)
        #expect(model.state == .succeeded)
        #expect(!model.hasPendingPurchaseSync)
        #expect(await purchasing.purchaseCount == 1)
        #expect(await purchasing.finishCount == 1)
        #expect(await repository.syncedIDs == ["tx-test", "tx-test"])
    }

    @Test("A server-expired purchase does not claim Premium success")
    func inactivePurchaseStaysVisible() async {
        let model = PaywallViewModel(context: .settingsUpgrade, purchasing: CountingPurchasing(),
                                     subscriptionRepository: RecoverySubscriptions(inactive: true))
        await model.onAppear()
        await model.purchase(.monthly)
        #expect(model.state != .succeeded)
        #expect(model.subscription?.isEntitledToPremium == false)
    }

    @Test("Restore reconciles all verified transactions in chronological order")
    func restoreDoesNotDependOnAppleEnumerationOrder() async {
        let repository = RecoverySubscriptions()
        let purchasing = CountingPurchasing()
        await purchasing.setRestoredPayloads()
        let model = PaywallViewModel(context: .settingsUpgrade, purchasing: purchasing,
                                     subscriptionRepository: repository)
        await model.restore()
        #expect(await repository.syncedIDs == ["older", "newer"])
        #expect(model.state == .succeeded)
    }
}

private actor CountingPurchasing: StoreKitPurchasing {
    private(set) var purchaseCount = 0
    private(set) var finishCount = 0
    private var restored: [AppStoreTransactionPayload] = []
    func offerings() async throws -> [PaywallOffering] { try await MockStoreKitPurchasing().offerings() }
    func purchase(_ productID: AstraProductID) async throws -> AppStoreTransactionPayload? {
        purchaseCount += 1
        return try await MockStoreKitPurchasing().purchase(productID)
    }
    func restoreEntitlements() async throws -> [AppStoreTransactionPayload] { restored }
    func finishTransaction(_ payload: AppStoreTransactionPayload) async { finishCount += 1 }
    func setRestoredPayloads() {
        guard var newer = MockStoreKitPurchasing().purchasePayload else { return }
        newer.transactionID = "newer"
        var older = newer
        older.transactionID = "older"
        older.purchaseDate = newer.purchaseDate.addingTimeInterval(-3600)
        restored = [newer, older]
    }
}

private actor RecoverySubscriptions: SubscriptionRepository {
    private var failures: Int
    private var inactive: Bool
    private(set) var syncedIDs: [String] = []
    init(failures: Int = 0, inactive: Bool = false) { self.failures = failures; self.inactive = inactive }
    func fetchCurrentSubscription() async throws -> Subscription {
        try await MockSubscriptionRepository(status: .expired).fetchCurrentSubscription()
    }
    func syncTransaction(_ payload: AppStoreTransactionPayload) async throws -> Subscription {
        syncedIDs.append(payload.transactionID)
        if failures > 0 { failures -= 1; throw AstraError.network("Temporary sync failure") }
        return Subscription(userID: UUID(), productID: payload.productID,
                            status: inactive ? .expired : .active,
                            expiresAt: inactive ? .now.addingTimeInterval(-1) : .now.addingTimeInterval(3600),
                            environment: .sandbox)
    }
    func restorePurchases() async throws -> Subscription { try await fetchCurrentSubscription() }
}
