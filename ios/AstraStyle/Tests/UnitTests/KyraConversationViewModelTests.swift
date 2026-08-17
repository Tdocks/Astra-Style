//
//  KyraConversationViewModelTests.swift
//  AstraStyleTests
//
//  Written against what the conversation screen PROMISES rather than how
//  it is implemented: a sent message either gains a reply or gains a
//  visible failure with retry; a suggested prompt is a real message;
//  offline is a stated condition, not a queue; analytics carries the
//  intent and never the text; and an action button only exists where the
//  app can honor it.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("KyraConversationViewModel")
@MainActor
struct KyraConversationViewModelTests {

    @Test("A new conversation is ready without touching the network")
    func newConversationLoadsInstantly() async {
        let model = makeModel()
        await model.onAppear()

        guard case .loaded = model.historyState else {
            Issue.record("expected .loaded, got \(model.historyState)")
            return
        }
        #expect(model.entries.isEmpty)
        #expect(model.showsSuggestedPrompts)
    }

    @Test("Sending appends the user's message and Kyra's structured reply")
    func sendAppendsEchoAndReply() async throws {
        let model = makeModel()
        await model.onAppear()
        model.draftText = "What should I wear tonight?"

        await model.sendDraft()

        #expect(model.entries.count == 2)
        #expect(model.entries[0].role == .user)
        #expect(model.entries[0].text == "What should I wear tonight?")
        #expect(model.entries[0].sendFailure == nil)
        #expect(model.entries[1].role == .assistant)
        #expect(!model.entries[1].suggestedActions.isEmpty)
        #expect(model.threadID != nil)
        #expect(model.draftText.isEmpty)
    }

    @Test("The reply's outfit card hydrates into the cited outfit's garments")
    func outfitCardHydrates() async throws {
        let model = makeModel()
        await model.onAppear()

        await model.send(prompt: "What should I wear tonight?")

        let reply = try #require(model.entries.last)
        let outfitCard = reply.cards.compactMap { card -> KyraOutfitCardModel? in
            if case .outfit(let outfitModel) = card { return outfitModel }
            return nil
        }.first
        let hydrated = try #require(outfitCard)
        #expect(hydrated.id == SampleData.heroOutfit.id)
        #expect(!hydrated.garments.isEmpty)
    }

    @Test("A tapped suggested prompt is a real message, not a pre-fill")
    func suggestedPromptSends() async throws {
        let model = makeModel()
        await model.onAppear()
        let prompt = try #require(KyraConversationViewModel.suggestedPrompts.first)

        await model.send(prompt: prompt)

        #expect(model.entries.count == 2)
        #expect(model.entries[0].role == .user)
        #expect(model.entries[0].text == prompt)
        #expect(!model.showsSuggestedPrompts)
    }

    @Test("Analytics records the intent and never the prompt text")
    func analyticsCarriesIntentOnly() async throws {
        let analytics = SpyAnalyticsClient()
        let model = makeModel(analytics: analytics)
        await model.onAppear()
        let prompt = "Something private about how I look"

        await model.send(prompt: prompt)

        let event = try #require(analytics.events.first)
        #expect(event.name == "kyra_prompt_sent")
        // The event's whole property bag is the intent — nothing else, and
        // in particular never the free text (spec §18).
        #expect(Set(event.properties.keys) == ["intent"])
        for value in event.properties.values {
            #expect(value != .string(prompt))
        }
    }

    @Test("A failed send stays visible, marked, and retryable — never silently lost")
    func failedSendIsKeptAndRetryable() async throws {
        let flaky = FlakyKyraRepository(failuresBeforeSuccess: 1)
        let model = makeModel(kyra: flaky)
        await model.onAppear()

        await model.send(prompt: "What should I wear tonight?")

        #expect(model.entries.count == 1)
        let failed = try #require(model.entries.first)
        #expect(failed.sendFailure != nil)
        #expect(failed.pending != nil)

        await model.retrySend(entryID: failed.id)

        #expect(model.entries.count == 2)
        #expect(model.entries[0].sendFailure == nil)
        #expect(model.entries[1].role == .assistant)
    }

    @Test("Offline blocks send with a stated condition instead of a queue")
    func offlineBlocksSend() async {
        let model = makeModel(offline: true)
        await model.onAppear()

        #expect(model.isOffline)
        model.draftText = "What should I wear tonight?"
        #expect(!model.canSendDraft)

        await model.send(prompt: "What should I wear tonight?")

        // Nothing was queued and nothing was silently dropped mid-flight —
        // the message never left the composer.
        #expect(model.entries.isEmpty)
    }

    @Test("Action kinds the app cannot honor are not performable")
    func unperformableKindsAreFiltered() async throws {
        let model = makeModel()
        await model.onAppear()
        await model.send(prompt: "What should I wear tonight?")
        let reply = try #require(model.entries.last)

        let wear = KyraSuggestedAction(id: "wear", label: "Wear This", kind: .wearOutfit)
        let studio = KyraSuggestedAction(id: "studio", label: "See It On You", kind: .startStudioGeneration)
        let schedule = KyraSuggestedAction(id: "sched", label: "Schedule", kind: .scheduleOutfit)

        #expect(model.canPerform(wear, in: reply))
        #expect(!model.canPerform(studio, in: reply))
        #expect(!model.canPerform(schedule, in: reply))

        // Without an outfit card in the message there is nothing for a
        // wear action to act on, so it must not render either.
        let cardless = KyraTranscriptEntry(role: .assistant, text: "Just advice.")
        #expect(!model.canPerform(wear, in: cardless))
    }

    @Test("Wear This records a real wear against the cited outfit, once")
    func wearActionRecordsWear() async throws {
        let outfits = KyraOutfitRepositorySpy()
        let model = makeModel(outfit: outfits)
        await model.onAppear()
        await model.send(prompt: "What should I wear tonight?")
        let reply = try #require(model.entries.last)
        let wear = try #require(reply.suggestedActions.first { $0.kind == .wearOutfit })

        await model.perform(wear, in: reply.id)
        await model.perform(wear, in: reply.id)

        #expect(outfits.wornOutfitIDs == [SampleData.heroOutfit.id])
        #expect(model.performedActionKeys.contains(model.actionKey(wear, entryID: reply.id)))
        #expect(model.actionNote != nil)
    }

    @Test("Save records a saved opinion, not a duplicate outfit row")
    func saveActionRecordsFeedback() async throws {
        let outfits = KyraOutfitRepositorySpy()
        let model = makeModel(outfit: outfits)
        await model.onAppear()
        await model.send(prompt: "What should I wear tonight?")
        let reply = try #require(model.entries.last)
        let save = KyraSuggestedAction(id: "save", label: "Save", kind: .saveOutfit)

        await model.perform(save, in: reply.id)

        #expect(outfits.feedback.count == 1)
        #expect(outfits.feedback.first?.signal == .saved)
        #expect(outfits.feedback.first?.targetID == SampleData.heroOutfit.id)
    }

    @Test("A card whose row cannot be loaded degrades to an honest unavailable card")
    func unloadableCardDegrades() async throws {
        let outfits = KyraOutfitRepositorySpy(failsFetches: true)
        let model = makeModel(outfit: outfits)
        await model.onAppear()

        await model.send(prompt: "What should I wear tonight?")

        let reply = try #require(model.entries.last)
        let card = try #require(reply.cards.first)
        guard case .unavailable(let unavailable) = card else {
            Issue.record("expected .unavailable, got \(card)")
            return
        }
        #expect(unavailable.isRetryable)
        #expect(!reply.rawCards.isEmpty)
    }
}

// MARK: - Helpers

@MainActor
private func makeModel(
    kyra: KyraRepository = MockKyraRepository(),
    outfit: OutfitRepository = MockOutfitRepository(),
    offline: Bool = false,
    analytics: AnalyticsClient = NoOpAnalyticsClient()
) -> KyraConversationViewModel {
    KyraConversationViewModel(
        threadID: nil,
        kyraRepository: kyra,
        outfitRepository: outfit,
        closetRepository: MockClosetRepository(),
        shoppingRepository: MockShoppingRepository(),
        imageURLResolver: MockClosetImageURLResolver(),
        networkMonitor: StaticNetworkReachabilityMonitor(offline: offline),
        analyticsClient: analytics
    )
}

/// Captures every event so the test can assert what analytics is — and is
/// not — told. `@unchecked Sendable` with main-actor-only access, the same
/// shape the other view-model suites in this target use.
private final class SpyAnalyticsClient: AnalyticsClient, @unchecked Sendable {
    private(set) var events: [AnalyticsEvent] = []

    func log(_ event: AnalyticsEvent) { events.append(event) }
    func identify(userID: UUID) {}
    func reset() {}
}

/// Fails the first N sends with a retryable network error, then delegates
/// to the real mock — the shape of a connection dropping mid-flight.
private final class FlakyKyraRepository: KyraRepository, @unchecked Sendable {
    private let base = MockKyraRepository()
    private var remainingFailures: Int

    init(failuresBeforeSuccess: Int) {
        remainingFailures = failuresBeforeSuccess
    }

    func send(threadID: UUID?, message: KyraOutgoingMessage) async throws -> KyraMessage {
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw AstraError.network("Couldn't reach Kyra.")
        }
        return try await base.send(threadID: threadID, message: message)
    }

    func fetchThreads() async throws -> [KyraThread] { try await base.fetchThreads() }
    func fetchMessages(threadID: UUID) async throws -> [KyraMessage] {
        try await base.fetchMessages(threadID: threadID)
    }
    func fetchMemories() async throws -> [StyleMemory] { try await base.fetchMemories() }
    func confirmMemoryProposal(_ proposal: KyraMemoryProposal, sourceMessageID: UUID) async throws -> StyleMemory {
        try await base.confirmMemoryProposal(proposal, sourceMessageID: sourceMessageID)
    }
    func deleteMemory(id: UUID) async throws { try await base.deleteMemory(id: id) }
}

/// Serves the sample hero outfit and records every wear/opinion written
/// against it; `failsFetches` makes hydration fail with a retryable error
/// so the unavailable degrade path can be exercised.
private final class KyraOutfitRepositorySpy: OutfitRepository, @unchecked Sendable {
    private let failsFetches: Bool
    private(set) var wornOutfitIDs: [UUID] = []
    private(set) var feedback: [StyleFeedback] = []

    init(failsFetches: Bool = false) {
        self.failsFetches = failsFetches
    }

    func fetchOutfit(id: UUID) async throws -> Outfit {
        guard !failsFetches else { throw AstraError.server("Couldn't load that outfit.") }
        return SampleData.heroOutfit
    }

    func fetchOutfitItems(outfitID: UUID) async throws -> [OutfitItem] {
        guard !failsFetches else { throw AstraError.server("Couldn't load that outfit.") }
        return SampleData.heroOutfitItems()
    }

    func recordWear(
        outfitID: UUID, wornAt: Date, occasion: String?, rating: Int?, feedback: String?
    ) async throws -> OutfitWear {
        wornOutfitIDs.append(outfitID)
        return OutfitWear(id: UUID(), outfitID: outfitID, userID: SampleData.userID, wornAt: wornAt)
    }

    func recordFeedback(
        targetType: StyleFeedbackTargetType,
        targetID: UUID,
        signal: StyleFeedbackSignal,
        reasonTags: [String],
        freeText: String?
    ) async throws -> StyleFeedback {
        let row = StyleFeedback(
            id: UUID(),
            userID: SampleData.userID,
            targetType: targetType,
            targetID: targetID,
            signal: signal,
            reasonTags: reasonTags,
            freeText: freeText
        )
        feedback.append(row)
        return row
    }

    func fetchOutfits() async throws -> [Outfit] { [SampleData.heroOutfit] }
    func fetchOutfits(ids: [UUID]) async throws -> [Outfit] { [SampleData.heroOutfit] }
    func generateOutfits(_ request: OutfitGenerationRequest) async throws -> [OutfitRecommendation] { [] }
    func rankOutfits(candidateOutfitIDs: [UUID], lockedClosetItemIDs: [UUID]) async throws -> [OutfitRecommendation] { [] }
    func saveOutfit(from recommendation: OutfitRecommendation, name: String?, closetItems: [ClosetItem]) async throws -> Outfit {
        throw AstraError.unimplemented("unused")
    }
    func updateOutfit(_ outfit: Outfit) async throws -> Outfit { outfit }
    func deleteOutfit(id: UUID) async throws {}
    func fetchDailyBrief(for date: Date) async throws -> DailyBrief? { nil }
    func generateDailyBrief(for date: Date, regenerate: Bool, weather: WeatherSnapshot?) async throws -> DailyBrief {
        throw AstraError.unimplemented("unused")
    }
    func generatePackingPlan(_ request: PackingRequest) async throws -> PackingPlan {
        throw AstraError.unimplemented("unused")
    }
}
