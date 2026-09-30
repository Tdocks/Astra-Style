//
//  SubscriptionManagementViewModel.swift
//  AstraStyle
//
//  Reads server-reconciled Premium status and restores StoreKit entitlements.
//

import Foundation
import Observation

@MainActor
@Observable
final class SubscriptionManagementViewModel {
    enum Phase: Sendable {
        case loading
        case ready(Subscription)
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var isRestoring = false
    private(set) var restoreError: String?

    private let purchasing: StoreKitPurchasing
    private let subscriptionRepository: SubscriptionRepository

    init(purchasing: StoreKitPurchasing, subscriptionRepository: SubscriptionRepository) {
        self.purchasing = purchasing
        self.subscriptionRepository = subscriptionRepository
    }

    func load() async {
        do {
            phase = .ready(try await subscriptionRepository.fetchCurrentSubscription())
        } catch let error as AstraError {
            phase = .failed(error.message)
        } catch {
            phase = .failed(String(localized: "Your plan details didn't load. Check your connection and try again.", comment: "Subscription management error"))
        }
    }

    func retry() async {
        phase = .loading
        await load()
    }

    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        restoreError = nil
        defer { isRestoring = false }
        do {
            let transactions = try await purchasing.restoreEntitlements()
            let subscription: Subscription
            if let transaction = transactions.last {
                subscription = try await subscriptionRepository.syncTransaction(transaction)
            } else {
                subscription = try await subscriptionRepository.restorePurchases()
            }
            phase = .ready(subscription)
        } catch let error as AstraError {
            restoreError = error.message
        } catch {
            restoreError = String(localized: "Purchases couldn't be restored. Try again.", comment: "Subscription restore error")
        }
    }
}
