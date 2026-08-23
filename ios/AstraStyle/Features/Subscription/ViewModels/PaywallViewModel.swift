//
//  PaywallViewModel.swift
//  AstraStyle
//
//  Charge at the 30-item cap. Never Wear This, never paste-evaluate.
//  Server row from subscriptions/sync is entitlement truth (ADR 0009).
//

import Foundation
import Observation

@MainActor
@Observable
public final class PaywallViewModel {
    public enum ViewState: Equatable, Sendable {
        case loading
        case ready
        case purchasing
        case succeeded
        case failed(String)
    }

    public let context: PaywallContext
    public private(set) var state: ViewState = .loading
    public private(set) var offerings: [PaywallOffering] = []
    public private(set) var subscription: Subscription?

    private let purchasing: StoreKitPurchasing
    private let subscriptionRepository: SubscriptionRepository

    public init(
        context: PaywallContext,
        purchasing: StoreKitPurchasing,
        subscriptionRepository: SubscriptionRepository
    ) {
        self.context = context
        self.purchasing = purchasing
        self.subscriptionRepository = subscriptionRepository
    }

    public func onAppear() async {
        do {
            offerings = try await purchasing.offerings()
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func purchase(_ productID: AstraProductID) async {
        state = .purchasing
        do {
            guard let payload = try await purchasing.purchase(productID) else {
                state = .ready
                return
            }
            subscription = try await subscriptionRepository.syncTransaction(payload)
            state = .succeeded
        } catch let error as AstraError {
            state = .failed(error.message)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func restore() async {
        state = .purchasing
        do {
            let payloads = try await purchasing.restoreEntitlements()
            if let payload = payloads.last {
                subscription = try await subscriptionRepository.syncTransaction(payload)
                state = .succeeded
                return
            }
            subscription = try await subscriptionRepository.restorePurchases()
            state = subscription?.isEntitledToPremium == true ? .succeeded : .ready
        } catch let error as AstraError {
            state = .failed(error.message)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public var showsLegalLinks: Bool { AstraLegal.isPublished }

    public var headline: String {
        String(localized: "Astra Style Premium", comment: "Paywall title")
    }

    public var subhead: String {
        switch context {
        case .kyraDailyLimit:
            String(
                localized: "Three conversations a day on us. Wear This stays free.",
                comment: "Paywall when Kyra's daily new-thread cap is hit"
            )
        case .studioQuota:
            String(
                localized: "One visual estimate on us. Wear This stays free.",
                comment: "Paywall when Studio's free trial is used"
            )
        case .closetLimit, .onboarding, .outfitGenerationLimit, .settingsUpgrade:
            String(
                localized: "Keep adding to the closet. Wear This stays free.",
                comment: "Paywall promise — the morning loop is not the charge"
            )
        }
    }
}
