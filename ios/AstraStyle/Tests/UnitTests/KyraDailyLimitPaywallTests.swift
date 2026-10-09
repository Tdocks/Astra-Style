//
//  KyraDailyLimitPaywallTests.swift
//  AstraStyleTests
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Kyra daily limit paywall")
@MainActor
struct KyraDailyLimitPaywallTests {
    @Test("A typed daily quota sets pendingPaywall to kyraDailyLimit")
    func quotaPresentsPaywall() async {
        let model = KyraConversationViewModel(
            threadID: nil,
            kyraRepository: CappedKyraRepository(),
            outfitRepository: MockOutfitRepository(),
            closetRepository: MockClosetRepository(),
            shoppingRepository: MockShoppingRepository(),
            imageURLResolver: MockClosetImageURLResolver(),
            networkMonitor: StaticNetworkReachabilityMonitor(offline: false),
            analyticsClient: NoOpAnalyticsClient()
        )
        await model.onAppear()
        model.draftText = "What should I wear tonight?"
        await model.sendDraft()
        #expect(model.pendingPaywall == .kyraDailyLimit)
    }

    @Test("A traffic throttle does not present the subscription paywall")
    func trafficThrottleDoesNotPresentPaywall() async {
        let model = KyraConversationViewModel(
            threadID: nil,
            kyraRepository: CappedKyraRepository(error: .rateLimited()),
            outfitRepository: MockOutfitRepository(),
            closetRepository: MockClosetRepository(),
            shoppingRepository: MockShoppingRepository(),
            imageURLResolver: MockClosetImageURLResolver(),
            networkMonitor: StaticNetworkReachabilityMonitor(offline: false),
            analyticsClient: NoOpAnalyticsClient()
        )
        await model.onAppear()
        model.draftText = "What should I wear tonight?"
        await model.sendDraft()
        #expect(model.pendingPaywall == nil)
    }
}

private final class CappedKyraRepository: KyraRepository, @unchecked Sendable {
    private let error: AstraError

    init(error: AstraError = AstraError(
        category: .subscriptionLimitReached,
        message: "Daily Kyra limit reached.",
        quotaDetails: AstraQuotaDetails(limit: "kyra_conversation_daily", limitCount: 3, remaining: 0, resetsAt: "2026-10-10T00:00:00Z")
    )) {
        self.error = error
    }

    func send(threadID: UUID?, message: KyraOutgoingMessage) async throws -> KyraMessage {
        throw error
    }
    func fetchThreads() async throws -> [KyraThread] { [] }
    func fetchMessages(threadID: UUID) async throws -> [KyraMessage] { [] }
    func fetchMemories() async throws -> [StyleMemory] { [] }
    func confirmMemoryProposal(_ proposal: KyraMemoryProposal, sourceMessageID: UUID) async throws -> StyleMemory {
        throw AstraError.unimplemented("unused")
    }
    func deleteMemory(id: UUID) async throws {}
}
