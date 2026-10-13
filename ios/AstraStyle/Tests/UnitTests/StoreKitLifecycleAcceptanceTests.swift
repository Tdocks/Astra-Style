import XCTest
import StoreKitTest
import StoreKit
@testable import AstraStyle

/// Apple's local StoreKit engine and live adapter; no hosted receipts or billing.
@MainActor
final class StoreKitLifecycleAcceptanceTests: XCTestCase {
    func testLocalPurchaseSyncRecoveryAndRestore() async throws {
        executionTimeAllowance = 60
        let session = try await configuredSession()
        defer { session.clearTransactions() }
        let adapter = LiveStoreKitPurchasing(appAccountTokenProvider: { SampleData.userID }, restoreSync: {})
        let unrelatedOwner = UUID()
        let observer = StoreKitTransactionObserver(subscriptionRepository: MockSubscriptionRepository(),
                                                   currentUserID: { unrelatedOwner })
        let updates = Task { await observer.observe() }
        defer { updates.cancel() }
        let offerings = try await adapter.offerings()
        guard offerings.count == 2 else { throw XCTSkip("Local StoreKit catalog is unavailable on this runtime") }
        let model = PaywallViewModel(context: .settingsUpgrade, purchasing: adapter,
                                     subscriptionRepository: MockSubscriptionRepository(syncFailures: 1))
        await model.purchase(.monthly)
        XCTAssertTrue(model.hasPendingPurchaseSync)
        let pending = await unfinishedIDs()
        XCTAssertFalse(pending.isEmpty, "Failed delivery must remain durable in StoreKit")
        await model.retryPurchaseSync()
        XCTAssertEqual(model.state, .succeeded)
        let delivered = await unfinishedIDs()
        XCTAssertTrue(delivered.isEmpty, "Finish only after backend acknowledgement")
        let restored = try await adapter.restoreEntitlements()
        XCTAssertEqual(restored.count, 1)
        XCTAssertFalse(restored.first?.signedTransactionInfo?.isEmpty ?? true)
    }

    func testLocalRenewalAndCancellationRetainCurrentAccess() async throws {
        let session = try await configuredSession()
        defer { session.clearTransactions() }
        let adapter = LiveStoreKitPurchasing(appAccountTokenProvider: { SampleData.userID }, restoreSync: {})
        let purchase = try await adapter.purchase(.monthly)
        let purchased = try XCTUnwrap(purchase)
        await adapter.finishTransaction(purchased)
        try session.forceRenewalOfSubscription(productIdentifier: AstraProductID.monthly.rawValue)
        let renewed = try await adapter.restoreEntitlements()
        XCTAssertEqual(renewed.count, 1)
        XCTAssertEqual(renewed.first?.originalTransactionID, purchased.originalTransactionID)
        let newestID = try XCTUnwrap(session.allTransactions().map(\.identifier).max())
        try session.disableAutoRenewForTransaction(identifier: newestID)
        XCTAssertEqual(session.allTransactions().first { $0.identifier == newestID }?.autoRenewingEnabled, false)
        let cancelled = try await adapter.restoreEntitlements()
        XCTAssertEqual(cancelled.count, 1, "Cancellation retains access through the paid period")
    }

    func testLocalRefundRevokesAccess() async throws {
        let session = try await configuredSession()
        defer { session.clearTransactions() }
        let adapter = LiveStoreKitPurchasing(appAccountTokenProvider: { SampleData.userID }, restoreSync: {})
        let purchase = try await adapter.purchase(.annual)
        let purchased = try XCTUnwrap(purchase)
        await adapter.finishTransaction(purchased)
        let newestID = try XCTUnwrap(session.allTransactions().map(\.identifier).max())
        try session.refundTransaction(identifier: newestID)
        let refunded = try await waitForRemoval(using: adapter)
        XCTAssertTrue(refunded.isEmpty)
    }

    func testDelayedApprovalIsDeliveredToTheMatchingOwner() async throws {
        executionTimeAllowance = 30
        let session = try await configuredSession()
        session.askToBuyEnabled = true
        defer { session.clearTransactions() }
        let repository = ApprovalSubscriptions()
        let observer = StoreKitTransactionObserver(subscriptionRepository: repository,
                                                   currentUserID: { SampleData.userID })
        let updates = Task { await observer.observe() }
        defer { updates.cancel() }
        let adapter = LiveStoreKitPurchasing(appAccountTokenProvider: { SampleData.userID }, restoreSync: {})
        let pending = try await adapter.purchase(.monthly)
        XCTAssertNil(pending, "Ask to Buy cannot grant access before approval")
        let request = try XCTUnwrap(session.allTransactions().first { $0.pendingAskToBuyConfirmation })
        try session.approveAskToBuyTransaction(identifier: request.identifier)
        for _ in 0..<20 {
            if await repository.deliveries > 0 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let count = await repository.deliveries
        XCTAssertEqual(count, 1, "Verified delayed approval must reach the matching owner's backend")
    }

    private func configuredSession() async throws -> SKTestSession {
        let configuration = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/AstraStyle.storekit")
        let session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.timeRate = .realTime
        session.clearTransactions()
        let adapter = LiveStoreKitPurchasing(appAccountTokenProvider: { nil }, restoreSync: {})
        let offerings = try await adapter.offerings()
        guard offerings.count == 2 else {
            throw XCTSkip("This runtime does not activate the local StoreKit catalog; run the documented iOS 27 acceptance target")
        }
        return session
    }

    private func unfinishedIDs() async -> [UInt64] {
        var ids: [UInt64] = []
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result { ids.append(transaction.id) }
        }
        return ids
    }

    private func waitForRemoval(using adapter: LiveStoreKitPurchasing) async throws -> [AppStoreTransactionPayload] {
        var payloads = try await adapter.restoreEntitlements()
        for _ in 0..<12 where !payloads.isEmpty {
            try await Task.sleep(for: .milliseconds(250))
            payloads = try await adapter.restoreEntitlements()
        }
        return payloads
    }
}

private actor ApprovalSubscriptions: SubscriptionRepository {
    private(set) var deliveries = 0
    func fetchCurrentSubscription() async throws -> Subscription {
        Subscription(userID: SampleData.userID, status: .expired)
    }
    func syncTransaction(_ payload: AppStoreTransactionPayload) async throws -> Subscription {
        deliveries += 1
        return Subscription(userID: SampleData.userID, productID: payload.productID,
                            status: .active, expiresAt: payload.expiresDate, environment: .sandbox)
    }
    func restorePurchases() async throws -> Subscription { try await fetchCurrentSubscription() }
}
