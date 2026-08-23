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
    @Test("A 429 on send sets pendingPaywall to kyraDailyLimit")
    func rateLimitPresentsPaywall() async {
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
}

private final class CappedKyraRepository: KyraRepository, @unchecked Sendable {
    func send(threadID: UUID?, message: KyraOutgoingMessage) async throws -> KyraMessage {
        throw AstraError.rateLimited(
            "You've used your 3 Kyra conversations for today. Upgrade to Astra Style Premium for unlimited conversations with Kyra."
        )
    }
    func fetchThreads() async throws -> [KyraThread] { [] }
    func fetchMessages(threadID: UUID) async throws -> [KyraMessage] { [] }
    func fetchMemories() async throws -> [StyleMemory] { [] }
    func confirmMemoryProposal(_ proposal: KyraMemoryProposal, sourceMessageID: UUID) async throws -> StyleMemory {
        throw AstraError.unimplemented("unused")
    }
    func deleteMemory(id: UUID) async throws {}
}
