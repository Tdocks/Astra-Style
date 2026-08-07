//
//  HomeBriefProvidingTests.swift
//  AstraStyleTests
//
//  What this file pins, after ADR 0014 removed guest mode: the signed-in
//  paths through `DefaultHomeBriefProvider` — a populated closet, a sparse
//  one, an unreadable one, and a regenerate.
//
//  The guest half is gone with the feature. It is worth knowing what it
//  was, because the shape recurs: a guest reached Home's ERROR state
//  because `loadTodayBrief` called `fetchCurrentProfile()` unconditionally
//  and a guest had no profile row. The fix branched early for guests — and
//  that branch then became the ONLY path that reached §6.11's empty state,
//  so every real user got an error screen where the spec calls for an
//  invitation. A branch added to fix one path can quietly become the only
//  path that is right.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("DefaultHomeBriefProvider")
struct HomeBriefProvidingTests {

    // MARK: - Signed-in path (no regression)

    @Test("A signed-in user still fetches the profile and gets a populated brief")
    func signedInUserGetsPopulatedBrief() async throws {
        let profileRepository = MockProfileRepository()
        let provider = DefaultHomeBriefProvider(
            outfitRepository: MockOutfitRepository(),
            profileRepository: profileRepository,
            closetRepository: MockClosetRepository(),
            weatherService: MockWeatherService(),
            calendarService: MockCalendarService()
        )

        let data = try await provider.loadTodayBrief(regenerate: false)

        #expect(data.greetingName == SampleData.profile.greetingName)
        #expect(data.primaryOutfit != nil)
        #expect(!data.needsMoreClosetItems)
        #expect(data.wardrobeScore != nil)
    }

    // MARK: - Sparse closet (spec §6.11 empty state)
    //
    // The defect these pin: for weeks the §6.11 empty state was reachable
    // only by a guest session. Every real user — including one who had
    // finished onboarding a minute earlier and owned nothing — went
    // straight to `generateDailyBrief`, whose Edge Function does not exist
    // (P4-HOME-02), and got an error screen reading "Something went wrong"
    // where the spec calls for "Let's build your first look".

    @Test("A signed-in user with fewer than five garments gets the empty state, not a brief request")
    func sparseClosetSkipsBriefGeneration() async throws {
        let outfitRepository = FailIfCalledOutfitRepository()
        let closetRepository = MockClosetRepository(
            items: Array(SampleData.closetItems.prefix(HomeBriefData.minimumItemsForOutfits - 1))
        )

        let provider = DefaultHomeBriefProvider(
            outfitRepository: outfitRepository,
            profileRepository: MockProfileRepository(),
            closetRepository: closetRepository,
            weatherService: MockWeatherService(),
            calendarService: MockCalendarService()
        )

        let data = try await provider.loadTodayBrief(regenerate: false)

        #expect(await outfitRepository.callCount == 0)
        #expect(data.needsMoreClosetItems)
        #expect(data.primaryOutfit == nil)
        // `.empty` carries its payload — the screen still greets him by
        // name rather than going blank.
        #expect(data.greetingName == SampleData.profile.greetingName)
    }

    /// The boundary the copy promises. "Add five pieces" must stop being
    /// true at the fifth piece, or the screen repeats itself at him.
    @Test("The fifth garment moves a signed-in user onto the real brief")
    func fifthGarmentLeavesTheEmptyState() async throws {
        let provider = DefaultHomeBriefProvider(
            outfitRepository: MockOutfitRepository(),
            profileRepository: MockProfileRepository(),
            closetRepository: MockClosetRepository(
                items: Array(SampleData.closetItems.prefix(HomeBriefData.minimumItemsForOutfits))
            ),
            weatherService: MockWeatherService(),
            calendarService: MockCalendarService()
        )

        let data = try await provider.loadTodayBrief(regenerate: false)

        #expect(data.primaryOutfit != nil)
        #expect(!data.needsMoreClosetItems)
    }

    /// An unreachable closet is not an empty one. Telling a man with forty
    /// garments to add five would be a worse lie than the error it
    /// replaced, so the count check declines to guess and the old path
    /// reports the failure honestly.
    @Test("A closet that cannot be read falls through rather than claiming the closet is empty")
    func unreadableClosetDoesNotFakeAnEmptyState() async throws {
        let provider = DefaultHomeBriefProvider(
            outfitRepository: MockOutfitRepository(),
            profileRepository: MockProfileRepository(),
            closetRepository: UnreachableClosetRepository(),
            weatherService: MockWeatherService(),
            calendarService: MockCalendarService()
        )

        let data = try await provider.loadTodayBrief(regenerate: false)

        #expect(data.primaryOutfit != nil)
        #expect(!data.needsMoreClosetItems)
    }

    // MARK: - Regenerate

    /// `POST /daily-brief/generate` is idempotent per `brief_date`
    /// (P4-HOME-02), so a regenerate that does not say so gets handed back
    /// the outfits the user just asked to replace — §6.11's regenerate
    /// control would look like it worked and change nothing.
    @Test("Regenerating asks the server to rebuild, rather than re-reading the stored brief")
    func regenerateIsForwardedToTheServer() async throws {
        let outfitRepository = RecordingOutfitRepository()
        let provider = DefaultHomeBriefProvider(
            outfitRepository: outfitRepository,
            profileRepository: MockProfileRepository(),
            closetRepository: MockClosetRepository(),
            weatherService: MockWeatherService(),
            calendarService: MockCalendarService()
        )

        _ = try await provider.loadTodayBrief(regenerate: true)
        #expect(await outfitRepository.regenerateFlags == [true])

        // And the ordinary path still asks for whatever already exists —
        // a retry after a dropped connection must not rebuild.
        _ = try await provider.loadTodayBrief(regenerate: false)
        #expect(await outfitRepository.regenerateFlags == [true, false])
    }

    @Test("A signed-in user whose profile fetch fails surfaces the error rather than an empty state")
    func signedInProfileFailurePropagates() async throws {
        let provider = DefaultHomeBriefProvider(
            outfitRepository: MockOutfitRepository(),
            profileRepository: AlwaysFailingProfileRepository(),
            closetRepository: MockClosetRepository(),
            weatherService: MockWeatherService(),
            calendarService: MockCalendarService()
        )

        await #expect(throws: AstraError.self) {
            _ = try await provider.loadTodayBrief(regenerate: false)
        }
    }
}

// MARK: - Test doubles

/// Fails loudly if called — pins that a closet too thin to dress anyone
/// never reaches `OutfitRepository` at all, rather than asking the server
/// for an outfit it cannot build and handling the failure afterwards.
private actor FailIfCalledOutfitRepository: OutfitRepository {
    private(set) var callCount = 0

    private func recordCall(_ function: String = #function) {
        callCount += 1
        Issue.record("OutfitRepository.\(function) must not be called for a closet below the outfit threshold")
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
    func generateDailyBrief(for date: Date, regenerate: Bool) async throws -> DailyBrief { recordCall(); throw AstraError.server("unused") }
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

/// `OutfitRepository` double that records the `regenerate` flag each call
/// carried. `fetchDailyBrief` returns nil so the provider always reaches
/// `generateDailyBrief` — the cached-brief branch is a different test's
/// subject, and letting it short-circuit here would make the assertion
/// pass for the wrong reason.
private actor RecordingOutfitRepository: OutfitRepository {
    private(set) var regenerateFlags: [Bool] = []

    func fetchOutfits() async throws -> [Outfit] { [] }
    func fetchOutfit(id: UUID) async throws -> Outfit { SampleData.heroOutfit }
    func fetchOutfits(ids: [UUID]) async throws -> [Outfit] { [] }
    func fetchOutfitItems(outfitID: UUID) async throws -> [OutfitItem] { [] }
    func generateOutfits(_ request: OutfitGenerationRequest) async throws -> [OutfitRecommendation] { [] }
    func rankOutfits(candidateOutfitIDs: [UUID], lockedClosetItemIDs: [UUID]) async throws -> [OutfitRecommendation] { [] }
    func saveOutfit(from recommendation: OutfitRecommendation, name: String?, closetItems: [ClosetItem]) async throws -> Outfit {
        SampleData.heroOutfit
    }
    func updateOutfit(_ outfit: Outfit) async throws -> Outfit { outfit }
    func deleteOutfit(id: UUID) async throws {}
    @discardableResult
    func recordWear(outfitID: UUID, wornAt: Date, occasion: String?, rating: Int?, feedback: String?) async throws -> OutfitWear {
        throw AstraError.unimplemented("unused")
    }
    func fetchDailyBrief(for date: Date) async throws -> DailyBrief? { nil }
    func generateDailyBrief(for date: Date, regenerate: Bool) async throws -> DailyBrief {
        regenerateFlags.append(regenerate)
        return DailyBrief(
            id: UUID(),
            userID: SampleData.profile.id,
            briefDate: date,
            primaryOutfitID: SampleData.heroOutfit.id
        )
    }
    func generatePackingPlan(_ request: PackingRequest) async throws -> PackingPlan {
        throw AstraError.unimplemented("unused")
    }
}

/// `ClosetRepository` double whose `fetchItems()` always fails — the
/// "we do not know how many garments he owns" case, which must not be
/// mistaken for "he owns none."
private struct UnreachableClosetRepository: ClosetRepository {
    func fetchItems() async throws -> [ClosetItem] { throw AstraError.network("The closet is unreachable.") }
    func fetchItem(id: UUID) async throws -> ClosetItem { throw AstraError.network("unused") }
    func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] { [] }
    func uploadCapturedImage(_ data: Data) async throws -> String { throw AstraError.network("unused") }
    func deleteCapturedImage(atPath storagePath: String) async throws { _ = storagePath }
    func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        throw AstraError.network("unused")
    }
    func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        throw AstraError.network("unused")
    }
    func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem { item }
    func updateItem(_ item: ClosetItem) async throws -> ClosetItem { item }
    func archiveItem(id: UUID) async throws {}
    func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem { throw AstraError.network("unused") }
    func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem {
        throw AstraError.network("unused")
    }
    func fetchWardrobeScore() async throws -> WardrobeScore { throw AstraError.network("unused") }
}
