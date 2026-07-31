//
//  HomeBriefProvidingTests.swift
//  AstraStyleTests
//
//  Defect (visual QA sweep): a guest landed on Home's error state because
//  `DefaultHomeBriefProvider.loadTodayBrief(regenerate:)` called
//  `profileRepository.fetchCurrentProfile()` unconditionally, and guests
//  have no server-side profile row at all (ADR 0011). These tests pin the
//  fix — a guest never touches `ProfileRepository` and gets the real empty
//  state — and guard against a signed-in regression in the same file.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("DefaultHomeBriefProvider — guest vs. signed-in (ADR 0011)")
struct HomeBriefProvidingTests {

    // MARK: - Guest path

    @Test("A guest brief never calls ProfileRepository or OutfitRepository, and yields the empty state")
    func guestBriefMakesNoProfileOrOutfitCall() async throws {
        let profileRepository = FailIfCalledProfileRepository()
        let outfitRepository = FailIfCalledOutfitRepository()
        let closetRepository = MockClosetRepository(items: [])

        let provider = DefaultHomeBriefProvider(
            outfitRepository: outfitRepository,
            profileRepository: profileRepository,
            closetRepository: closetRepository,
            weatherService: MockWeatherService(),
            calendarService: MockCalendarService(),
            isGuest: { true }
        )

        let data = try await provider.loadTodayBrief(regenerate: false)

        #expect(await profileRepository.callCount == 0)
        #expect(await outfitRepository.callCount == 0)

        // The real empty state (spec §6.11 "Add five pieces..."), not an
        // error — this is exactly what `HomeViewModel.load(regenerate:)`
        // checks to choose `.empty` over `.loaded`.
        #expect(data.needsMoreClosetItems)
        #expect(data.primaryOutfit == nil)
        #expect(data.brief.primaryOutfitID == nil)
    }

    @Test("A guest brief reads the local closet through ClosetRepository, not a hardcoded value")
    func guestBriefReadsLocalCloset() async throws {
        // `fetchWardrobeScore()` throwing (as `GuestClosetRepository` always
        // does) must not surface as an error either — it degrades to `nil`
        // like every other optional module.
        let closetRepository = ThrowingWardrobeScoreClosetRepository(
            items: [
                ClosetItem(id: UUID(), userID: UUID(), name: "Item 1", category: .top, laundryState: .laundry),
                ClosetItem(id: UUID(), userID: UUID(), name: "Item 2", category: .bottom, laundryState: .clean)
            ]
        )

        let provider = DefaultHomeBriefProvider(
            outfitRepository: FailIfCalledOutfitRepository(),
            profileRepository: FailIfCalledProfileRepository(),
            closetRepository: closetRepository,
            weatherService: MockWeatherService(),
            calendarService: MockCalendarService(),
            isGuest: { true }
        )

        let data = try await provider.loadTodayBrief(regenerate: false)

        #expect(data.laundryAlertItemCount == 1)
        #expect(data.wardrobeScore == nil)
    }

    // MARK: - Signed-in path (no regression)

    @Test("A signed-in user still fetches the profile and gets a populated brief")
    func signedInUserGetsPopulatedBrief() async throws {
        let profileRepository = MockProfileRepository()
        let provider = DefaultHomeBriefProvider(
            outfitRepository: MockOutfitRepository(),
            profileRepository: profileRepository,
            closetRepository: MockClosetRepository(),
            weatherService: MockWeatherService(),
            calendarService: MockCalendarService(),
            isGuest: { false }
        )

        let data = try await provider.loadTodayBrief(regenerate: false)

        #expect(data.greetingName == SampleData.profile.greetingName)
        #expect(data.primaryOutfit != nil)
        #expect(!data.needsMoreClosetItems)
        #expect(data.wardrobeScore != nil)
    }

    @Test("A signed-in user whose profile fetch fails surfaces the error rather than an empty state")
    func signedInProfileFailurePropagates() async throws {
        let provider = DefaultHomeBriefProvider(
            outfitRepository: MockOutfitRepository(),
            profileRepository: AlwaysFailingProfileRepository(),
            closetRepository: MockClosetRepository(),
            weatherService: MockWeatherService(),
            calendarService: MockCalendarService(),
            isGuest: { false }
        )

        await #expect(throws: AstraError.self) {
            _ = try await provider.loadTodayBrief(regenerate: false)
        }
    }
}

// MARK: - Test doubles

/// Fails loudly (via `Issue.record`) if any method is called — used to pin
/// "a guest brief makes no profile fetch at all", not just "the happy path
/// doesn't need one."
private actor FailIfCalledProfileRepository: ProfileRepository {
    private(set) var callCount = 0

    private func recordCall(_ function: String = #function) {
        callCount += 1
        Issue.record("ProfileRepository.\(function) must never be called for a guest session (ADR 0011)")
    }

    func fetchCurrentProfile() async throws -> Profile {
        recordCall()
        return SampleData.profile
    }

    func updateProfile(_ profile: Profile) async throws -> Profile {
        recordCall()
        return profile
    }

    func fetchStyleProfile() async throws -> StyleProfile? {
        recordCall()
        return nil
    }

    func updateStyleProfile(_ styleProfile: StyleProfile) async throws -> StyleProfile {
        recordCall()
        return styleProfile
    }

    func fetchBodyProfile() async throws -> BodyProfile? {
        recordCall()
        return nil
    }

    func updateBodyProfile(_ bodyProfile: BodyProfile) async throws -> BodyProfile {
        recordCall()
        return bodyProfile
    }

    func fetchLifestyleProfile() async throws -> LifestyleProfile? {
        recordCall()
        return nil
    }

    func updateLifestyleProfile(_ lifestyleProfile: LifestyleProfile) async throws -> LifestyleProfile {
        recordCall()
        return lifestyleProfile
    }

    func completeOnboarding(_ payload: OnboardingCompletionPayload) async throws -> Profile {
        recordCall()
        return SampleData.profile
    }

    func generateStyleDNA() async throws -> StyleDNA {
        recordCall()
        return SampleData.styleDNA
    }

    func uploadReferenceImage(_ imageData: Data) async throws -> String {
        recordCall()
        return "users/guest/references/never.jpg"
    }

    func exportPersonalData() async throws -> URL {
        recordCall()
        return URL(fileURLWithPath: "/dev/null")
    }
}

/// Fails loudly if called — pins that a guest brief never reaches
/// `OutfitRepository` either, since there is no server-generated Daily
/// Brief to fetch without an Edge Function round trip a guest can't make.
private actor FailIfCalledOutfitRepository: OutfitRepository {
    private(set) var callCount = 0

    private func recordCall(_ function: String = #function) {
        callCount += 1
        Issue.record("OutfitRepository.\(function) must never be called for a guest session (ADR 0011)")
    }

    func fetchOutfits() async throws -> [Outfit] { recordCall(); return [] }
    func fetchOutfit(id: UUID) async throws -> Outfit { recordCall(); throw AstraError.server("unused") }
    func fetchOutfits(ids: [UUID]) async throws -> [Outfit] { recordCall(); return [] }
    func fetchOutfitItems(outfitID: UUID) async throws -> [OutfitItem] { recordCall(); return [] }
    func generateOutfits(_ request: OutfitGenerationRequest) async throws -> [OutfitRecommendation] { recordCall(); return [] }
    func rankOutfits(candidateOutfitIDs: [UUID], lockedClosetItemIDs: [UUID]) async throws -> [OutfitRecommendation] { recordCall(); return [] }
    func saveOutfit(from recommendation: OutfitRecommendation, name: String?, closetItems: [ClosetItem]) async throws -> Outfit {
        recordCall()
        throw AstraError.server("unused")
    }
    func updateOutfit(_ outfit: Outfit) async throws -> Outfit { recordCall(); throw AstraError.server("unused") }
    func deleteOutfit(id: UUID) async throws { recordCall() }
    @discardableResult
    func recordWear(outfitID: UUID, wornAt: Date, occasion: String?, rating: Int?, feedback: String?) async throws -> OutfitWear {
        recordCall()
        throw AstraError.server("unused")
    }
    func fetchDailyBrief(for date: Date) async throws -> DailyBrief? { recordCall(); return nil }
    func generateDailyBrief(for date: Date) async throws -> DailyBrief { recordCall(); throw AstraError.server("unused") }
    func generatePackingPlan(_ request: PackingRequest) async throws -> PackingPlan {
        recordCall()
        throw AstraError.server("unused")
    }
}

/// `ProfileRepository` double whose `fetchCurrentProfile()` always fails —
/// used to confirm a signed-in profile failure still propagates as a
/// visible error rather than being swallowed.
private struct AlwaysFailingProfileRepository: ProfileRepository {
    func fetchCurrentProfile() async throws -> Profile { throw AstraError.server("boom") }
    func updateProfile(_ profile: Profile) async throws -> Profile { throw AstraError.server("boom") }
    func fetchStyleProfile() async throws -> StyleProfile? { throw AstraError.server("boom") }
    func updateStyleProfile(_ styleProfile: StyleProfile) async throws -> StyleProfile { throw AstraError.server("boom") }
    func fetchBodyProfile() async throws -> BodyProfile? { throw AstraError.server("boom") }
    func updateBodyProfile(_ bodyProfile: BodyProfile) async throws -> BodyProfile { throw AstraError.server("boom") }
    func fetchLifestyleProfile() async throws -> LifestyleProfile? { throw AstraError.server("boom") }
    func updateLifestyleProfile(_ lifestyleProfile: LifestyleProfile) async throws -> LifestyleProfile { throw AstraError.server("boom") }
    func completeOnboarding(_ payload: OnboardingCompletionPayload) async throws -> Profile { throw AstraError.server("boom") }
    func generateStyleDNA() async throws -> StyleDNA { throw AstraError.server("boom") }
    func uploadReferenceImage(_ imageData: Data) async throws -> String { throw AstraError.server("boom") }
    func exportPersonalData() async throws -> URL { throw AstraError.server("boom") }
}

/// `ClosetRepository` double that behaves like `MockClosetRepository` for
/// everything except `fetchWardrobeScore()`, which always throws — mirrors
/// `GuestClosetRepository.fetchWardrobeScore()`'s real behavior ("Wardrobe
/// Score isn't available in guest mode") without depending on SwiftData.
private actor ThrowingWardrobeScoreClosetRepository: ClosetRepository {
    private var items: [ClosetItem]

    init(items: [ClosetItem]) {
        self.items = items
    }

    func fetchItems() async throws -> [ClosetItem] { items }
    func fetchItem(id: UUID) async throws -> ClosetItem {
        guard let item = items.first(where: { $0.id == id }) else {
            throw AstraError.server("not found")
        }
        return item
    }
    func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] { [] }
    func analyzeItem(imageData: Data, imageType: ClosetImageType) async throws -> ClosetItemAnalysisResult {
        throw AstraError.validation("unused")
    }
    func batchAnalyzeItems(imageDataList: [Data]) async throws -> [ClosetItemAnalysisResult] {
        throw AstraError.validation("unused")
    }
    func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        items.append(item)
        return item
    }
    func updateItem(_ item: ClosetItem) async throws -> ClosetItem { item }
    func archiveItem(id: UUID) async throws {}
    func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem {
        guard let item = items.first(where: { $0.id == id }) else {
            throw AstraError.server("not found")
        }
        return item
    }
    func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem {
        guard let item = items.first(where: { $0.id == id }) else {
            throw AstraError.server("not found")
        }
        return item
    }
    func fetchWardrobeScore() async throws -> WardrobeScore {
        throw AstraError.validation("Wardrobe Score isn't available in guest mode. Create an account to unlock it.")
    }
}
