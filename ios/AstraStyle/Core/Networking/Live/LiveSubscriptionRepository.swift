//
//  LiveSubscriptionRepository.swift
//  AstraStyle
//
//  `subscriptions` reads go through Postgrest; syncing a StoreKit
//  transaction is an orchestration call (spec §14 `subscriptions/sync`)
//  because the server must verify it against Apple's servers and
//  reconcile it with App Store Server Notifications (spec §16).
//

import Foundation
import Supabase

public final class LiveSubscriptionRepository: SubscriptionRepository, @unchecked Sendable {
    private let apiClient: AstraAPIClient
    private let supabase: SupabaseClient

    public init(apiClient: AstraAPIClient, supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current)) {
        self.apiClient = apiClient
        self.supabase = supabase
    }

    public func fetchCurrentSubscription() async throws -> Subscription {
        do {
            return try await supabase.from("subscriptions").select().single().execute().value
        } catch {
            // No row yet means the user has never subscribed — treat as
            // free tier rather than surfacing an error.
            let session = try? await supabase.auth.session
            return Subscription(userID: session?.user.id ?? UUID(), status: .none)
        }
    }

    public func syncTransaction(_ payload: AppStoreTransactionPayload) async throws -> Subscription {
        try await apiClient.send(.syncSubscriptions, body: payload, as: Subscription.self)
    }

    public func restorePurchases() async throws -> Subscription {
        struct Body: Encodable, Sendable {
            let restore: Bool = true
        }
        return try await apiClient.send(.syncSubscriptions, body: Body(), as: Subscription.self)
    }
}
