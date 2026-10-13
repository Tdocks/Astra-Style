import Foundation
import StoreKit

public protocol SubscriptionTransactionObserving: Sendable {
    func observe() async
    func reconcileUnfinished() async
}

/// Delayed purchases and renewals are delivered even if the paywall has closed.
/// Keep a failed delivery unfinished so reconnect/relaunch can safely retry it.
public actor StoreKitTransactionObserver: SubscriptionTransactionObserving {
    private let subscriptionRepository: any SubscriptionRepository
    private let currentUserID: @Sendable () async -> UUID?
    private var inFlight: Set<UInt64> = []

    public init(subscriptionRepository: any SubscriptionRepository,
                currentUserID: @escaping @Sendable () async -> UUID?) {
        self.subscriptionRepository = subscriptionRepository
        self.currentUserID = currentUserID
    }

    public func observe() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [self] in
                for await result in Transaction.updates {
                    guard !Task.isCancelled else { return }
                    await deliver(result)
                }
            }
            await reconcileUnfinished()
            await group.waitForAll()
        }
    }

    public func reconcileUnfinished() async {
        for await result in Transaction.unfinished {
            guard !Task.isCancelled else { return }
            await deliver(result)
        }
    }

    private func deliver(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result,
              AstraProductID(rawValue: transaction.productID) != nil,
              !inFlight.contains(transaction.id),
              let ownerID = await currentUserID(),
              transaction.appAccountToken == ownerID else { return }
        // The account lookup yields; check again before claiming this delivery.
        guard !inFlight.contains(transaction.id) else { return }
        inFlight.insert(transaction.id)
        defer { inFlight.remove(transaction.id) }
        do {
            let payload = LiveStoreKitPurchasing.payload(from: transaction, signedInfo: result.jwsRepresentation)
            let subscription = try await subscriptionRepository.syncTransaction(payload)
            guard subscription.userID == ownerID, !Task.isCancelled,
                  await currentUserID() == ownerID else { return }
            await transaction.finish()
        } catch {
            // No local entitlement is granted, and Apple's unfinished record
            // remains the durable source of truth for the next recovery attempt.
        }
    }
}
