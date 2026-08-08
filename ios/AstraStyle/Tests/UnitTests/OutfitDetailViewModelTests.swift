//
//  OutfitDetailViewModelTests.swift
//  AstraStyleTests
//
//  Spec §6.12 "Outfit detail" and `P4-OUTFIT-11`'s acceptance criteria
//  ("all action buttons are wired", "Visualize opens the Studio flow
//  entry point"). Repository doubles are hand-rolled rather than reusing
//  `Core/Mocks/Mock*Repository` for the same reason
//  `ClosetItemDetailViewModelTests` gives: the mocks cannot be made to
//  FAIL, and several assertions below are specifically about what the
//  screen does when a read or write does not land.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("OutfitDetailViewModel — spec §6.12 outfit detail")
@MainActor
struct OutfitDetailViewModelTests {

    // MARK: - Fixtures

    private func makeOutfit(
        id: UUID = UUID(),
        name: String = "Client Meeting, Elevated Casual",
        description: String? = "Grounded by the knit polo, kept light by the trousers."
    ) -> Outfit {
        Outfit(id: id, userID: UUID(), name: name, description: description, compatibilityScore: 92)
    }

    private func makeClosetItem(id: UUID = UUID(), name: String = "Knit Polo") -> ClosetItem {
        ClosetItem(id: id, userID: UUID(), name: name, category: .top, primaryColor: "olive")
    }

    private func makeViewModel(
        outfit: Outfit,
        items: [OutfitItem] = [],
        outfitRepository: StubOutfitRepository? = nil,
        closetRepository: StubOutfitDetailClosetRepository = StubOutfitDetailClosetRepository(),
        imageResolver: StubOutfitDetailImageResolver = StubOutfitDetailImageResolver(),
        profileRepository: StubOutfitDetailProfileRepository = StubOutfitDetailProfileRepository(),
        analyticsClient: RecordingAnalyticsClient = RecordingAnalyticsClient()
    ) -> (viewModel: OutfitDetailViewModel, outfitRepository: StubOutfitRepository) {
        let repository = outfitRepository ?? StubOutfitRepository(outfit: outfit, items: items)
        let viewModel = OutfitDetailViewModel(
            outfitID: outfit.id,
            outfitRepository: repository,
            closetRepository: closetRepository,
            closetImageURLResolver: imageResolver,
            profileRepository: profileRepository,
            analyticsClient: analyticsClient,
            networkMonitor: StaticNetworkReachabilityMonitor(offline: false)
        )
        return (viewModel, repository)
    }

    // MARK: - Loading

    @Test("Loading resolves each owned item's closet row and its signed photo URL")
    func loadingResolvesOwnedItemsAndPhotos() async throws {
        let outfit = makeOutfit()
        let item = makeClosetItem()
        let outfitItem = OutfitItem(outfitID: outfit.id, closetItemID: item.id, role: .top, sortOrder: 0)
        let image = ClosetItemImage(id: UUID(), closetItemID: item.id, imageType: .front, storagePath: "closet/\(item.id).jpg", isPrimary: true)
        let url = try #require(URL(string: "https://example.com/signed.jpg"))

        let closetRepository = StubOutfitDetailClosetRepository(items: [item], imagesByItemID: [item.id: [image]])
        let imageResolver = StubOutfitDetailImageResolver(urls: [image.storagePath: url])

        let made = makeViewModel(outfit: outfit, items: [outfitItem], closetRepository: closetRepository, imageResolver: imageResolver)
        await made.viewModel.onAppear()

        let detail = try #require(made.viewModel.state.detail)
        #expect(detail.outfit.id == outfit.id)
        #expect(detail.closetItemsByID[item.id]?.id == item.id)
        #expect(detail.imageURLsByClosetItemID[item.id] == url)
        #expect(detail.ownedClosetItems.map(\.id) == [item.id])
    }

    @Test("A profile read failure falls back to imperial units rather than failing the screen")
    func profileFailureFallsBackToImperial() async {
        let outfit = makeOutfit()
        let profileRepository = StubOutfitDetailProfileRepository(error: AstraError.server("profile unavailable"))

        let made = makeViewModel(outfit: outfit, profileRepository: profileRepository)
        await made.viewModel.onAppear()

        let detail = made.viewModel.state.detail
        #expect(detail?.units == .imperial)
    }

    @Test("A signing failure degrades to no photos — the outfit still loads")
    func imageSigningFailureDegradesToNoPhotos() async throws {
        let outfit = makeOutfit()
        let item = makeClosetItem()
        let outfitItem = OutfitItem(outfitID: outfit.id, closetItemID: item.id, role: .top, sortOrder: 0)
        let image = ClosetItemImage(id: UUID(), closetItemID: item.id, imageType: .front, storagePath: "closet/\(item.id).jpg", isPrimary: true)

        let closetRepository = StubOutfitDetailClosetRepository(items: [item], imagesByItemID: [item.id: [image]])
        let imageResolver = StubOutfitDetailImageResolver(error: AstraError.server("Storage is unavailable."))

        let made = makeViewModel(outfit: outfit, items: [outfitItem], closetRepository: closetRepository, imageResolver: imageResolver)
        await made.viewModel.onAppear()

        let detail = try #require(made.viewModel.state.detail)
        #expect(detail.closetItemsByID[item.id]?.id == item.id)
        #expect(detail.imageURLsByClosetItemID.isEmpty)
    }

    @Test("An outfit that fails to load surfaces as .failed")
    func outfitFetchFailureSurfacesAsFailed() async {
        let outfit = makeOutfit()
        let repository = StubOutfitRepository(outfit: outfit, items: [], fetchOutfitError: AstraError.server("not found"))

        let made = makeViewModel(outfit: outfit, outfitRepository: repository)
        await made.viewModel.onAppear()

        guard case .failed = made.viewModel.state else {
            Issue.record("Expected .failed, got \(made.viewModel.state)")
            return
        }
    }

    // MARK: - Mark Worn

    @Test("Marking worn records a wear against the outfit and logs analytics on success")
    func markWornRecordsWearAndLogsAnalytics() async {
        let outfit = makeOutfit()
        let repository = StubOutfitRepository(outfit: outfit, items: [])
        let analyticsClient = RecordingAnalyticsClient()

        let made = makeViewModel(outfit: outfit, outfitRepository: repository, analyticsClient: analyticsClient)
        await made.viewModel.onAppear()
        await made.viewModel.markWorn(at: .now)

        let recordCount = await repository.recordWearCallCount
        let lastOutfitID = await repository.lastRecordWearOutfitID
        #expect(recordCount == 1)
        #expect(lastOutfitID == outfit.id)
        #expect(made.viewModel.actionError == nil)
        #expect(analyticsClient.loggedEvents.count == 1)
    }

    @Test("A failed mark worn surfaces actionError without invalidating the loaded outfit")
    func markWornFailureSurfacesActionErrorOnly() async {
        let outfit = makeOutfit()
        let repository = StubOutfitRepository(outfit: outfit, items: [], recordWearError: AstraError.network("offline"))

        let made = makeViewModel(outfit: outfit, outfitRepository: repository)
        await made.viewModel.onAppear()
        await made.viewModel.markWorn(at: .now)

        #expect(made.viewModel.actionError != nil)
        // The outfit itself is still there — a failed action does not
        // replace loaded content with an error screen.
        #expect(made.viewModel.state.detail?.outfit.id == outfit.id)
    }

    @Test("clearActionError clears a surfaced failure")
    func clearActionErrorClearsFailure() async {
        let outfit = makeOutfit()
        let repository = StubOutfitRepository(outfit: outfit, items: [], recordWearError: AstraError.network("offline"))

        let made = makeViewModel(outfit: outfit, outfitRepository: repository)
        await made.viewModel.onAppear()
        await made.viewModel.markWorn(at: .now)
        made.viewModel.clearActionError()

        #expect(made.viewModel.actionError == nil)
    }
}

// MARK: - Stubs
//
// Same rationale as `ClosetItemDetailViewModelTests`' `StubClosetRepository`:
// an `actor` for `StubOutfitRepository` because `OutfitRepository` is
// `Sendable` and deliberately not `@MainActor`, so a mutable class here
// would be the exact data race Swift 6 strict concurrency exists to catch.
// `StaticNetworkReachabilityMonitor` (`Core/Utilities
// /NetworkReachabilityMonitoring.swift`) is reused rather than re-declared
// — it already does exactly what an outfit-detail-scoped stub would.

private actor StubOutfitRepository: OutfitRepository {
    private let outfit: Outfit
    private let items: [OutfitItem]
    private let fetchOutfitError: (any Error & Sendable)?
    private let recordWearError: (any Error & Sendable)?

    private(set) var recordWearCallCount = 0
    private(set) var lastRecordWearOutfitID: UUID?

    init(
        outfit: Outfit,
        items: [OutfitItem] = [],
        fetchOutfitError: (any Error & Sendable)? = nil,
        recordWearError: (any Error & Sendable)? = nil
    ) {
        self.outfit = outfit
        self.items = items
        self.fetchOutfitError = fetchOutfitError
        self.recordWearError = recordWearError
    }

    func fetchOutfits() async throws -> [Outfit] {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func fetchOutfit(id: UUID) async throws -> Outfit {
        if let fetchOutfitError { throw fetchOutfitError }
        return outfit
    }

    func fetchOutfits(ids: [UUID]) async throws -> [Outfit] {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func fetchOutfitItems(outfitID: UUID) async throws -> [OutfitItem] {
        items
    }

    func generateOutfits(_ request: OutfitGenerationRequest) async throws -> [OutfitRecommendation] {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func rankOutfits(candidateOutfitIDs: [UUID], lockedClosetItemIDs: [UUID]) async throws -> [OutfitRecommendation] {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func saveOutfit(from recommendation: OutfitRecommendation, name: String?, closetItems: [ClosetItem]) async throws -> Outfit {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func updateOutfit(_ outfit: Outfit) async throws -> Outfit {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func deleteOutfit(id: UUID) async throws {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    @discardableResult
    func recordWear(outfitID: UUID, wornAt: Date, occasion: String?, rating: Int?, feedback: String?) async throws -> OutfitWear {
        recordWearCallCount += 1
        lastRecordWearOutfitID = outfitID
        if let recordWearError { throw recordWearError }
        return OutfitWear(id: UUID(), outfitID: outfitID, userID: outfit.userID, wornAt: wornAt, occasion: occasion, rating: rating, feedback: feedback)
    }

    func fetchDailyBrief(for date: Date) async throws -> DailyBrief? {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func generateDailyBrief(for date: Date, regenerate: Bool, weather: WeatherSnapshot?) async throws -> DailyBrief {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func generatePackingPlan(_ request: PackingRequest) async throws -> PackingPlan {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }
}

private struct StubOutfitDetailClosetRepository: ClosetRepository {
    var items: [ClosetItem] = []
    var imagesByItemID: [UUID: [ClosetItemImage]] = [:]
    var fetchItemsError: (any Error & Sendable)?

    func fetchItems() async throws -> [ClosetItem] {
        if let fetchItemsError { throw fetchItemsError }
        return items
    }

    func fetchItem(id: UUID) async throws -> ClosetItem {
        guard let item = items.first(where: { $0.id == id }) else {
            throw AstraError.server("No such item in this stub.")
        }
        return item
    }

    func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] {
        imagesByItemID[itemID] ?? []
    }

    func uploadCapturedImage(_ data: Data) async throws -> String {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func deleteCapturedImage(atPath storagePath: String) async throws {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func updateItem(_ item: ClosetItem) async throws -> ClosetItem {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func archiveItem(id: UUID) async throws {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func fetchWardrobeScore() async throws -> WardrobeScore {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }
}

private struct StubOutfitDetailImageResolver: ClosetImageURLResolving {
    var urls: [String: URL] = [:]
    var error: (any Error & Sendable)?

    func resolve(storagePath: String) async throws -> URL {
        if let error { throw error }
        guard let url = urls[storagePath] else {
            throw AstraError.server("Couldn't load that photo.")
        }
        return url
    }

    func resolve(storagePaths: [String]) async throws -> [String: URL] {
        if let error { throw error }
        return urls.filter { storagePaths.contains($0.key) }
    }
}

private struct StubOutfitDetailProfileRepository: ProfileRepository {
    var profile = Profile(id: UUID(), units: .imperial)
    var error: (any Error & Sendable)?

    func fetchCurrentProfile() async throws -> Profile {
        if let error { throw error }
        return profile
    }

    func updateProfile(_ profile: Profile) async throws -> Profile {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func fetchStyleProfile() async throws -> StyleProfile? {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func updateStyleProfile(_ styleProfile: StyleProfile) async throws -> StyleProfile {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func fetchBodyProfile() async throws -> BodyProfile? {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func updateBodyProfile(_ bodyProfile: BodyProfile) async throws -> BodyProfile {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func fetchLifestyleProfile() async throws -> LifestyleProfile? {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func updateLifestyleProfile(_ lifestyleProfile: LifestyleProfile) async throws -> LifestyleProfile {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func completeOnboarding(_ payload: OnboardingCompletionPayload) async throws -> Profile {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func generateStyleDNA() async throws -> StyleDNA {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func uploadReferenceImage(_ imageData: Data) async throws -> String {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }

    func exportPersonalData() async throws -> URL {
        throw AstraError.unimplemented("Not exercised by outfit detail.")
    }
}

/// A `final class ... @unchecked Sendable`, matching `LiveAnalyticsClient`:
/// `AnalyticsClient.log(_:)` is a synchronous, non-`async` protocol
/// requirement, so an `actor` cannot conform to it directly, and every
/// call in these tests happens from `@MainActor` code, exactly as
/// `LiveAnalyticsClient` assumes.
private final class RecordingAnalyticsClient: AnalyticsClient, @unchecked Sendable {
    private(set) var loggedEvents: [AnalyticsEvent] = []

    func log(_ event: AnalyticsEvent) {
        loggedEvents.append(event)
    }

    func identify(userID: UUID) {}

    func reset() {}
}
