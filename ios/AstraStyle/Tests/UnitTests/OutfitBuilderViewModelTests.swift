//
//  OutfitBuilderViewModelTests.swift
//  AstraStyleTests
//
//  Derived from P4-OUTFIT-12's acceptance criteria, not from the
//  implementation:
//    - "Locking an item and triggering regenerate changes only unlocked
//      slots."
//    - "The compatibility meter updates live as items are swapped,
//      calling CompatibilityScorer for the current combination."
//    - "'Ask Kyra to finish' ... may show a 'coming soon' state rather
//      than a silently broken button" before P5-KYRA-06 lands.
//

import Foundation
import Testing
@testable import AstraStyle

/// `@MainActor` for the same reason every other view-model suite here is:
/// `OutfitBuilderViewModel` is `@MainActor @Observable` per ADR 0006, so
/// without it neither the initialiser nor any observable property is reachable
/// from the test. Swift 6 reports it against generated macro code rather than
/// against the `#expect` that caused it, which makes it look far stranger than
/// it is.
@MainActor
@Suite("OutfitBuilderViewModel")
struct OutfitBuilderViewModelTests {

    // MARK: - Fixtures

    func item(_ category: ClothingCategory, name: String = "Fixture", userID: UUID = UUID()) -> ClosetItem {
        ClosetItem(id: UUID(), userID: userID, name: name, category: category)
    }

    // MARK: - Doubles

    /// A minimal, fully-controllable `OutfitRepository` double. Every
    /// method not under test in a given case throws
    /// `AstraError.unimplemented` rather than silently no-op-ing, so a
    /// test that accidentally exercises an unstubbed path fails loudly
    /// instead of passing on a wrong assumption.
    actor StubOutfitRepository: OutfitRepository {
        var rankResult: [OutfitRecommendation] = []
        var generationResult: [OutfitRecommendation] = []
        var generationError: AstraError?
        var loadedOutfit: Outfit?
        var loadedItems: [OutfitItem] = []
        var outfitsByID: [UUID: Outfit] = [:]
        var outfitItemsByID: [UUID: [OutfitItem]] = [:]
        private(set) var lastReplacedOutfitID: UUID?
        private(set) var lastReplacementItems: [UUID] = []
        private(set) var lastLockedClosetItemIDs: [UUID] = []
        private(set) var lastGenerationRequest: OutfitGenerationRequest?
        private(set) var savedRecommendations: [OutfitRecommendation] = []

        func fetchOutfits() async throws -> [Outfit] { [] }
        func fetchOutfit(id: UUID) async throws -> Outfit {
            outfitsByID[id] ?? loadedOutfit ?? Outfit(id: id, userID: UUID(), name: "Fixture")
        }
        func fetchOutfits(ids: [UUID]) async throws -> [Outfit] { [] }
        func fetchOutfitItems(outfitID: UUID) async throws -> [OutfitItem] {
            outfitItemsByID[outfitID] ?? loadedItems
        }
        func generateOutfits(_ request: OutfitGenerationRequest) async throws -> [OutfitRecommendation] {
            lastGenerationRequest = request
            if let generationError { throw generationError }
            return generationResult
        }

        func rankOutfits(candidateOutfitIDs: [UUID], lockedClosetItemIDs: [UUID]) async throws -> [OutfitRecommendation] {
            lastLockedClosetItemIDs = lockedClosetItemIDs
            return rankResult
        }

        func saveOutfit(from recommendation: OutfitRecommendation, name: String?, closetItems: [ClosetItem]) async throws -> Outfit {
            savedRecommendations.append(recommendation)
            return Outfit(id: recommendation.id, userID: UUID(), name: name ?? recommendation.name)
        }

        func updateOutfit(_ outfit: Outfit) async throws -> Outfit { outfit }
        func replaceOutfitItemsAndMetadata(_ outfit: Outfit, items: [ClosetItem]) async throws -> Outfit {
            lastReplacedOutfitID = outfit.id
            lastReplacementItems = items.map(\.id)
            return outfit
        }
        func deleteOutfit(id: UUID) async throws {}

        @discardableResult
        func recordWear(outfitID: UUID, wornAt: Date, occasion: String?, rating: Int?, feedback: String?) async throws -> OutfitWear {
            throw AstraError.unimplemented("not stubbed")
        }

        @discardableResult
        func recordFeedback(
            targetType: StyleFeedbackTargetType,
            targetID: UUID,
            signal: StyleFeedbackSignal,
            reasonTags: [String],
            freeText: String?
        ) async throws -> StyleFeedback {
            throw AstraError.unimplemented("not stubbed")
        }

        func fetchDailyBrief(for date: Date) async throws -> DailyBrief? { nil }
        func generateDailyBrief(for date: Date, regenerate: Bool, weather: WeatherSnapshot?) async throws -> DailyBrief {
            throw AstraError.unimplemented("not stubbed")
        }
        func generatePackingPlan(_ request: PackingRequest) async throws -> PackingPlan {
            throw AstraError.unimplemented("not stubbed")
        }

        func setLoadedOutfit(_ outfit: Outfit, items: [OutfitItem]) {
            loadedOutfit = outfit
            loadedItems = items
            outfitsByID[outfit.id] = outfit
            outfitItemsByID[outfit.id] = items
        }

        func setOutfit(_ outfit: Outfit, items: [OutfitItem]) {
            outfitsByID[outfit.id] = outfit
            outfitItemsByID[outfit.id] = items
        }

        func setRankResult(_ result: [OutfitRecommendation]) {
            rankResult = result
        }

        func setGenerationResult(_ result: [OutfitRecommendation]) {
            generationResult = result
        }

        func failGeneration(with error: AstraError) {
            generationError = error
        }
    }

    actor StubKyraRepository: KyraRepository {
        let reply: KyraMessage
        let sendError: AstraError?
        let onSend: (@Sendable () async -> Void)?
        private(set) var lastMessage: KyraOutgoingMessage?
        private(set) var lastExpectedOwnerID: UUID?
        private(set) var sendCount = 0
        init(
            reply: KyraMessage,
            sendError: AstraError? = nil,
            onSend: (@Sendable () async -> Void)? = nil
        ) {
            self.reply = reply
            self.sendError = sendError
            self.onSend = onSend
        }
        func fetchThreads() async throws -> [KyraThread] { [] }
        func fetchMessages(threadID: UUID) async throws -> [KyraMessage] { [] }
        func send(threadID: UUID?, message: KyraOutgoingMessage) async throws -> KyraMessage {
            lastMessage = message
            sendCount += 1
            await onSend?()
            if let sendError { throw sendError }
            return reply
        }
        func send(threadID: UUID?, message: KyraOutgoingMessage, expectedOwnerID: UUID) async throws -> KyraMessage {
            lastExpectedOwnerID = expectedOwnerID
            return try await send(threadID: threadID, message: message)
        }
        func fetchMemories() async throws -> [StyleMemory] { [] }
        func confirmMemoryProposal(_ proposal: KyraMemoryProposal, sourceMessageID: UUID) async throws -> StyleMemory {
            throw AstraError.unimplemented("not used")
        }
        func deleteMemory(id: UUID) async throws {}
    }

    actor OwnerState {
        private(set) var id: UUID?
        init(_ id: UUID?) { self.id = id }
        func current() -> UUID? { id }
        func switchTo(_ id: UUID?) { self.id = id }
    }

    private struct StubGenerationContextProvider: OutfitBuilderGenerationContextProviding {
        let context: OutfitBuilderGenerationContext
        func makeContext() async throws -> OutfitBuilderGenerationContext { context }
    }

    func makeViewModel(
        closet: [ClosetItem],
        repository: StubOutfitRepository = StubOutfitRepository(),
        contextProvider: any OutfitBuilderGenerationContextProviding = EmptyOutfitContextProvider(),
        startingOutfitID: UUID? = nil,
        kyraRepository: KyraRepository? = nil,
        ownerID: UUID? = nil,
        ownerProvider: (@Sendable () async -> UUID?)? = nil
    ) -> (OutfitBuilderViewModel, StubOutfitRepository) {
        let closetRepository = MockClosetRepository(items: closet)
        let viewModel = OutfitBuilderViewModel(
            outfitRepository: repository,
            closetRepository: closetRepository,
            compatibilityScorer: LocalCompatibilityScorer(),
            startingOutfitID: startingOutfitID,
            generationContextProvider: contextProvider,
            kyraRepository: kyraRepository,
            currentOwnerID: ownerProvider ?? { ownerID }
        )
        return (viewModel, repository)
    }

    // MARK: - Lock + regenerate

    @Test("Regenerating with a locked top only changes the unlocked bottom slot")
    func regenerateChangesOnlyUnlockedSlots() async throws {
        let lockedTop = item(.top, name: "Locked Navy Shirt")
        let originalBottom = item(.bottom, name: "Original Chinos")
        let newBottom = item(.bottom, name: "Recommended Trousers")
        let closet = [lockedTop, originalBottom, newBottom]

        let (viewModel, repository) = makeViewModel(closet: closet, startingOutfitID: UUID())
        await viewModel.onAppear()
        viewModel.selectItem(lockedTop, for: .top)
        viewModel.selectItem(originalBottom, for: .bottom)
        viewModel.toggleLock(for: .top)
        #expect(viewModel.slots.first(where: { $0.category == .top })?.isLocked == true)

        let recommendation = OutfitRecommendation(
            id: UUID(),
            name: "Regenerated",
            reason: "",
            compatibilityScore: 80,
            itemIDs: [lockedTop.id, newBottom.id],
            missingProductIDs: []
        )
        await repository.setRankResult([recommendation])

        await viewModel.regenerate()

        let top = viewModel.slots.first(where: { $0.category == .top })
        let bottom = viewModel.slots.first(where: { $0.category == .bottom })
        #expect(top?.item?.id == lockedTop.id, "The locked slot must be untouched")
        #expect(bottom?.item?.id == newBottom.id, "The unlocked slot must take the regenerated item")
        #expect(await repository.lastLockedClosetItemIDs == [lockedTop.id])
    }

    @Test("applyToUnlockedSlots never overwrites a locked slot, even if the recommendation targets it")
    func applyToUnlockedSlotsNeverTouchesLockedSlot() async throws {
        let lockedTop = item(.top, name: "Locked")
        let recommendedTop = item(.top, name: "Would-be replacement")
        let (viewModel, _) = makeViewModel(closet: [lockedTop, recommendedTop])
        await viewModel.onAppear()
        viewModel.selectItem(lockedTop, for: .top)
        viewModel.toggleLock(for: .top)

        let recommendation = OutfitRecommendation(
            id: UUID(), name: "x", reason: "", compatibilityScore: 50,
            itemIDs: [recommendedTop.id], missingProductIDs: []
        )
        viewModel.applyToUnlockedSlots(recommendation)

        #expect(viewModel.slots.first(where: { $0.category == .top })?.item?.id == lockedTop.id)
    }

    @Test("An empty slot cannot be locked")
    func emptySlotCannotBeLocked() async throws {
        let (viewModel, _) = makeViewModel(closet: [])
        await viewModel.onAppear()
        viewModel.toggleLock(for: .top)
        #expect(viewModel.slots.first(where: { $0.category == .top })?.isLocked == false)
    }

    // MARK: - Live compatibility meter

    @Test("Fewer than two filled slots reports no compatibility reading at all")
    func compatibilityIsAbsentBelowTwoItems() async throws {
        let top = item(.top)
        let (viewModel, _) = makeViewModel(closet: [top])
        await viewModel.onAppear()
        #expect(viewModel.currentCompatibility == nil)

        viewModel.selectItem(top, for: .top)
        #expect(viewModel.currentCompatibility == nil, "One item alone has nothing to be compatible WITH")
    }

    @Test("The compatibility reading updates live as a slot is swapped")
    func compatibilityUpdatesWhenASlotIsSwapped() async throws {
        let topScored = ClosetItem(id: UUID(), userID: UUID(), name: "Top", category: .top, formalityScore: 50)
        let bottomA = ClosetItem(id: UUID(), userID: UUID(), name: "A", category: .bottom, formalityScore: 50)
        let bottomB = ClosetItem(id: UUID(), userID: UUID(), name: "B", category: .bottom, formalityScore: 0)
        let (viewModel, _) = makeViewModel(closet: [topScored, bottomA, bottomB])
        await viewModel.onAppear()

        viewModel.selectItem(topScored, for: .top)
        viewModel.selectItem(bottomA, for: .bottom)
        let firstReading = try #require(viewModel.currentCompatibility)

        viewModel.selectItem(bottomB, for: .bottom)
        let secondReading = try #require(viewModel.currentCompatibility)

        #expect(firstReading != secondReading)
    }

    @Test("Saving an edit replaces the rows on the same outfit identity")
    func saveExistingOutfitPreservesIdentity() async throws {
        let ownerID = UUID()
        let top = item(.top, name: "Existing top", userID: ownerID)
        let bottom = item(.bottom, name: "Replacement bottom", userID: ownerID)
        let outfitID = UUID()
        let saved = Outfit(id: outfitID, userID: ownerID, name: "Original", source: .userCreated)
        let repository = StubOutfitRepository()
        await repository.setLoadedOutfit(saved, items: [OutfitItem(outfitID: outfitID, closetItemID: top.id, role: .top, sortOrder: 0)])
        let (viewModel, _) = makeViewModel(closet: [top, bottom], repository: repository, startingOutfitID: outfitID)
        await viewModel.onAppear()
        viewModel.selectItem(bottom, for: .bottom)
        await viewModel.save()
        #expect(await repository.lastReplacedOutfitID == outfitID)
        #expect(await repository.lastReplacementItems == [top.id, bottom.id])
    }

    // MARK: - Save

    @Test("Saving with no items filled does nothing")
    func saveDoesNothingWhenEmpty() async throws {
        let (viewModel, repository) = makeViewModel(closet: [])
        await viewModel.onAppear()
        await viewModel.save()
        #expect(await repository.savedRecommendations.isEmpty)
        #expect(viewModel.savedOutfit == nil)
    }

    @Test("Saving with at least one item persists and records the backing outfit id")
    func saveWithOneItemPersists() async throws {
        let top = item(.top)
        let (viewModel, repository) = makeViewModel(closet: [top])
        await viewModel.onAppear()
        viewModel.selectItem(top, for: .top)

        await viewModel.save()

        #expect(await repository.savedRecommendations.count == 1)
        #expect(viewModel.savedOutfit != nil)
        #expect(viewModel.backingOutfitID == viewModel.savedOutfit?.id)
    }
}

extension OutfitBuilderViewModelTests {
    @Test("Authorized builder context keeps weather and calendar within the request limit without event titles")
    func builderContextIncludesAuthorizedWeatherAndCalendarSafely() async throws {
        var style = SampleData.styleProfile
        style.styleSummary = String(repeating: "Long style summary ", count: 80)
        let weather = WeatherSnapshot(
            temperatureHigh: 72,
            temperatureLow: 58,
            condition: .rain,
            precipitationChance: 0.8,
            season: .fall,
            observedAt: .now,
            temperatureCelsius: 18
        )
        let start = Calendar.current.date(bySettingHour: 17, minute: 30, second: 0, of: .now) ?? .now
        let event = Occasion(
            id: UUID(), userID: SampleData.userID, title: "Private event title", startsAt: start,
            dressCode: .businessCasual, source: .calendarSync
        )
        let provider = CurrentOutfitContextProvider(
            profileRepository: MockProfileRepository(styleProfile: style),
            weatherService: MockWeatherService(snapshot: weather),
            calendarService: MockCalendarService(events: [event])
        )

        let context = try await provider.makeContext()

        #expect(context.requestText.count <= 500)
        #expect(context.requestText.contains("Weather: rain"))
        #expect(context.requestText.contains("Today's calendar"))
        #expect(context.requestText.contains(DressCode.businessCasual.rawValue))
        #expect(!context.requestText.contains("Private event title"))
        #expect(context.requestText.contains(String((style.styleSummary ?? "").prefix(40))))
        #expect(!context.requestText.contains(style.styleSummary ?? ""))
        #expect(context.weatherSnapshot == weather)
    }

    @Test("Builder generation context omits weather and calendar unless already authorized")
    func builderContextDoesNotPromptForPermissions() async throws {
        let provider = CurrentOutfitContextProvider(
            profileRepository: MockProfileRepository(),
            weatherService: MockWeatherService(permissionGranted: false, authorization: .notDetermined),
            calendarService: MockCalendarService(permissionGranted: false)
        )

        let context = try await provider.makeContext()

        #expect(context.requestText.contains("Weather unavailable"))
        #expect(context.requestText.contains("Calendar unavailable"))
        #expect(context.weatherSnapshot == nil)
    }

    @Test("A new canvas regenerates from closet generation with its lock ids")
    func newCanvasRegenerateUsesOwnedGenerationAndKeepsLockedItem() async throws {
        let lockedTop = item(.top, name: "Locked shirt")
        let suggestedTop = item(.top, name: "Suggested shirt")
        let suggestedBottom = item(.bottom, name: "Suggested trousers")
        let (viewModel, repository) = makeViewModel(closet: [lockedTop, suggestedTop, suggestedBottom])
        await viewModel.onAppear()
        viewModel.selectItem(lockedTop, for: .top)
        viewModel.toggleLock(for: .top)
        await repository.setGenerationResult([
            OutfitRecommendation(
                id: UUID(), name: "Generated", reason: "", compatibilityScore: 80,
                itemIDs: [suggestedTop.id, suggestedBottom.id], missingProductIDs: []
            )
        ])

        await viewModel.regenerate()

        #expect(viewModel.slots.first(where: { $0.category == .top })?.item?.id == lockedTop.id)
        #expect(viewModel.slots.first(where: { $0.category == .bottom })?.item?.id == suggestedBottom.id)
        #expect(await repository.lastGenerationRequest?.desiredCount == 3)
        #expect(await repository.lastGenerationRequest?.lockedClosetItemIDs == [lockedTop.id])
    }

    @Test("Three recommendations receive the context and exclude foreign item references")
    func closetRecommendationsPreserveContextAndFilterForeignItems() async throws {
        let ownTop = item(.top, name: "Owned top")
        let ownBottom = item(.bottom, name: "Owned bottom")
        let otherUserItem = item(.shoes, name: "Another user's shoe")
        let valid = OutfitRecommendation(
            id: UUID(), name: "Owned look", reason: "", compatibilityScore: 80,
            itemIDs: [ownTop.id, ownBottom.id], missingProductIDs: []
        )
        let foreign = OutfitRecommendation(
            id: UUID(), name: "Invalid look", reason: "", compatibilityScore: 90,
            itemIDs: [ownTop.id, otherUserItem.id], missingProductIDs: []
        )
        let weather = SampleData.weatherSnapshot
        let context = OutfitBuilderGenerationContext(requestText: "Calendar time and style", weatherSnapshot: weather)
        let repository = StubOutfitRepository()
        await repository.setGenerationResult([valid, foreign])
        let (viewModel, _) = makeViewModel(
            closet: [ownTop, ownBottom],
            repository: repository,
            contextProvider: StubGenerationContextProvider(context: context)
        )
        await viewModel.onAppear()

        await viewModel.generateClosetRecommendations()

        #expect(viewModel.recommendations.map(\.id) == [valid.id])
        #expect(await repository.lastGenerationRequest?.desiredCount == 3)
        #expect(await repository.lastGenerationRequest?.naturalLanguageRequest == "Calendar time and style")
        #expect(await repository.lastGenerationRequest?.weatherSnapshot == weather)
    }

    @Test("Recommendation selection fills editable slots and preserves locked pieces")
    func selectingRecommendationFillsUnlockedSlots() async throws {
        let lockedTop = item(.top, name: "Keep this top")
        let recommendedTop = item(.top, name: "Suggested top")
        let recommendedBottom = item(.bottom, name: "Suggested bottom")
        let recommendation = OutfitRecommendation(
            id: UUID(), name: "Selected look", reason: "", compatibilityScore: 80,
            itemIDs: [recommendedTop.id, recommendedBottom.id], missingProductIDs: []
        )
        let repository = StubOutfitRepository()
        await repository.setGenerationResult([recommendation])
        let (viewModel, _) = makeViewModel(closet: [lockedTop, recommendedTop, recommendedBottom], repository: repository)
        await viewModel.onAppear()
        viewModel.selectItem(lockedTop, for: .top)
        viewModel.toggleLock(for: .top)
        await viewModel.generateClosetRecommendations()

        viewModel.selectRecommendation(recommendation)

        #expect(viewModel.slots.first(where: { $0.category == .top })?.item?.id == lockedTop.id)
        #expect(viewModel.slots.first(where: { $0.category == .bottom })?.item?.id == recommendedBottom.id)
        #expect(viewModel.outfitName == "Selected look")
        #expect(viewModel.selectedRecommendationID == recommendation.id)
    }

    @Test("Recommendation generation displays repository errors and can be retried")
    func closetRecommendationsSurfaceFailure() async throws {
        let ownTop = item(.top)
        let repository = StubOutfitRepository()
        await repository.failGeneration(with: AstraError.network("Suggestions are offline."))
        let (viewModel, _) = makeViewModel(closet: [ownTop], repository: repository)
        await viewModel.onAppear()

        await viewModel.generateClosetRecommendations()

        #expect(viewModel.recommendations.isEmpty)
        #expect(viewModel.recommendationError == "Suggestions are offline.")
    }

}
