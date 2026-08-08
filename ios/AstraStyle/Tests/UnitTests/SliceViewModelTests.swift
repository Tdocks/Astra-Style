//
//  SliceViewModelTests.swift
//  AstraStyleTests
//
//  Drives `SliceViewModel` end to end against mock repositories — never
//  the network (per the vertical-slice build instructions) — walking the
//  exact narrative the slice exists to prove: signed out -> signing in ->
//  signed in -> (garments) loading -> loaded -> add a garment -> generate
//  an outfit -> mark it worn, plus the corresponding error/offline paths.
//

import Foundation
import Testing
@testable import AstraStyle

// MARK: - Test doubles

/// Configurable `AppleSignInProviding` double — never presents real UI.
private actor StubAppleSignIn: AppleSignInProviding {
    enum Outcome: Sendable {
        case success(AppleSignInResult)
        case failure(AstraError)
    }

    private var outcome: Outcome

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func performSignIn() async throws -> AppleSignInResult {
        switch outcome {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}

/// Configurable `AuthRepository` double. Only the methods `SliceViewModel`
/// actually calls are meaningfully implemented; the rest exist purely to
/// satisfy the protocol.
private actor StubAuthRepository: AuthRepository {
    var signInResult: Result<AuthSession, AstraError>
    var restoreResult: Result<AuthSession?, AstraError> = .success(nil)
    private(set) var signOutCallCount = 0

    init(signInResult: Result<AuthSession, AstraError>) {
        self.signInResult = signInResult
    }

    func signInWithApple(identityToken: String, nonce: String) async throws -> AuthSession {
        try signInResult.get()
    }

    func requestEmailOTP(email: String) async throws {}

    func verifyEmailOTP(email: String, code: String) async throws -> AuthSession {
        try signInResult.get()
    }

    func continueAsGuest() async throws -> AuthSession {
        throw AstraError(category: .unknown, message: "not used by the slice")
    }

    func migrateGuestToAccount(identityToken: String, nonce: String) async throws -> AuthSession {
        try signInResult.get()
    }

    func restoreSession() async throws -> AuthSession? {
        try restoreResult.get()
    }

    func signOut() async throws {
        signOutCallCount += 1
    }

    func deleteAccount() async throws {}
}

/// Configurable `ClosetRepository` double.
private actor StubClosetRepository: ClosetRepository {
    var fetchResult: Result<[ClosetItem], AstraError>
    var createResult: Result<ClosetItem, AstraError>?

    init(fetchResult: Result<[ClosetItem], AstraError>, createResult: Result<ClosetItem, AstraError>? = nil) {
        self.fetchResult = fetchResult
        self.createResult = createResult
    }

    func fetchItems() async throws -> [ClosetItem] {
        try fetchResult.get()
    }

    func fetchItem(id: UUID) async throws -> ClosetItem {
        throw AstraError(category: .unknown, message: "not used by the slice")
    }

    func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] { [] }

    func uploadCapturedImage(_ data: Data) async throws -> String {
        _ = data
        return "users/test/closet/stub.jpg"
    }

    func deleteCapturedImage(atPath storagePath: String) async throws { _ = storagePath }

    func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        throw AstraError(category: .unknown, message: "not used by the slice — no camera/Vision in the slice")
    }

    func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch { ClosetItemAnalysisBatch(results: []) }

    func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        try (createResult ?? .success(item)).get()
    }

    func updateItem(_ item: ClosetItem) async throws -> ClosetItem { item }

    func archiveItem(id: UUID) async throws {}

    func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem {
        throw AstraError(category: .unknown, message: "not used by the slice")
    }

    func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem {
        throw AstraError(category: .unknown, message: "not used by the slice")
    }

    func fetchWardrobeScore() async throws -> WardrobeScore {
        WardrobeScore(overall: 0, versatility: 0, fitConfidence: 0, occasionCoverage: 0, colorCohesion: 0, wearUtilization: 0, condition: 0, redundancyControl: 0)
    }
}

/// Configurable `OutfitRepository` double.
private actor StubOutfitRepository: OutfitRepository {
    var generateResult: Result<[OutfitRecommendation], AstraError>
    var saveOutfitError: AstraError?
    var recordWearResult: Result<OutfitWear, AstraError>
    private(set) var recordWearCallCount = 0
    private(set) var saveOutfitCallCount = 0

    init(
        generateResult: Result<[OutfitRecommendation], AstraError> = .success([]),
        saveOutfitError: AstraError? = nil,
        recordWearResult: Result<OutfitWear, AstraError>? = nil
    ) {
        self.generateResult = generateResult
        self.saveOutfitError = saveOutfitError
        self.recordWearResult = recordWearResult ?? .success(
            OutfitWear(id: UUID(), outfitID: UUID(), userID: UUID(), wornAt: .now)
        )
    }

    func fetchOutfits() async throws -> [Outfit] { [] }
    func fetchOutfit(id: UUID) async throws -> Outfit {
        throw AstraError(category: .unknown, message: "not used by the slice")
    }
    func fetchOutfits(ids: [UUID]) async throws -> [Outfit] { [] }
    func fetchOutfitItems(outfitID: UUID) async throws -> [OutfitItem] { [] }

    func generateOutfits(_ request: OutfitGenerationRequest) async throws -> [OutfitRecommendation] {
        try generateResult.get()
    }

    func rankOutfits(candidateOutfitIDs: [UUID], lockedClosetItemIDs: [UUID]) async throws -> [OutfitRecommendation] {
        try generateResult.get()
    }

    func saveOutfit(from recommendation: OutfitRecommendation, name: String?, closetItems: [ClosetItem]) async throws -> Outfit {
        saveOutfitCallCount += 1
        if let saveOutfitError {
            throw saveOutfitError
        }
        return Outfit(
            id: recommendation.id,
            userID: UUID(),
            name: name ?? recommendation.name,
            description: recommendation.reason,
            compatibilityScore: recommendation.compatibilityScore,
            source: .aiGenerated
        )
    }

    func updateOutfit(_ outfit: Outfit) async throws -> Outfit { outfit }
    func deleteOutfit(id: UUID) async throws {}

    @discardableResult
    /// `P4-OUTFIT-14` added this verb to `OutfitRepository`. Echoes; this
    /// suite never exercises feedback.
    func recordFeedback(
        targetType: StyleFeedbackTargetType,
        targetID: UUID,
        signal: StyleFeedbackSignal,
        reasonTags: [String],
        freeText: String?
    ) async throws -> StyleFeedback {
        StyleFeedback(
            id: UUID(), userID: UUID(), targetType: targetType, targetID: targetID,
            signal: signal, reasonTags: reasonTags, freeText: freeText, createdAt: .now
        )
    }

    func recordWear(outfitID: UUID, wornAt: Date, occasion: String?, rating: Int?, feedback: String?) async throws -> OutfitWear {
        recordWearCallCount += 1
        return try recordWearResult.get()
    }

    func fetchDailyBrief(for date: Date) async throws -> DailyBrief? { nil }
    func generateDailyBrief(for date: Date, regenerate: Bool, weather: WeatherSnapshot?) async throws -> DailyBrief {
        throw AstraError(category: .unknown, message: "not used by the slice")
    }
    func generatePackingPlan(_ request: PackingRequest) async throws -> PackingPlan {
        throw AstraError(category: .unknown, message: "not used by the slice")
    }
}

/// Always reports online — the offline-specific test overrides this.
private struct StubReachability: NetworkReachabilityMonitoring {
    let offline: Bool
    func isOffline() async -> Bool { offline }
}

// MARK: - Fixtures

private func sampleSession(userID: UUID = UUID()) -> AuthSession {
    AuthSession(userID: userID, accessToken: "token", refreshToken: "refresh", expiresAt: .distantFuture)
}

private func sampleClosetItem(userID: UUID, category: ClothingCategory = .top, name: String = "Navy Sweater") -> ClosetItem {
    ClosetItem(id: UUID(), userID: userID, name: name, category: category, primaryColor: "navy")
}

// MARK: - Tests

@MainActor
@Suite("SliceViewModel state transitions")
struct SliceViewModelTests {

    @Test("Starts signed out with an empty closet")
    func initialState() {
        let userID = UUID()
        let viewModel = SliceViewModel(
            authRepository: StubAuthRepository(signInResult: .success(sampleSession(userID: userID))),
            closetRepository: StubClosetRepository(fetchResult: .success([])),
            outfitRepository: StubOutfitRepository(),
            appleSignIn: StubAppleSignIn(outcome: .success(AppleSignInResult(identityToken: "tok", rawNonce: "nonce"))),
            networkMonitor: StubReachability(offline: false)
        )

        #expect(viewModel.authPhase == .signedOut)
        #expect(!viewModel.isSignedIn)
        #expect(viewModel.garmentsState == .empty)
        #expect(!viewModel.canGenerateOutfit)
    }

    @Test("Sign in with Apple: signed out -> signing in -> signed in, then loads garments (loading -> loaded)")
    func signInThenLoadsGarments() async {
        let userID = UUID()
        let item = sampleClosetItem(userID: userID)
        let viewModel = SliceViewModel(
            authRepository: StubAuthRepository(signInResult: .success(sampleSession(userID: userID))),
            closetRepository: StubClosetRepository(fetchResult: .success([item])),
            outfitRepository: StubOutfitRepository(),
            appleSignIn: StubAppleSignIn(outcome: .success(AppleSignInResult(identityToken: "tok", rawNonce: "nonce"))),
            networkMonitor: StubReachability(offline: false)
        )

        #expect(viewModel.authPhase == .signedOut)

        await viewModel.signInWithApple()

        #expect(viewModel.authPhase == .signedIn(userID: userID))
        #expect(viewModel.isSignedIn)
        // `loadGarments()` runs to completion inside `signInWithApple()`,
        // so by the time we resume here it has already gone
        // loading -> loaded.
        #expect(viewModel.garmentsState == .loaded([item]))
        #expect(viewModel.canGenerateOutfit)
    }

    @Test("Sign in failure stays signed out and surfaces the error")
    func signInFailureStaysSignedOut() async {
        let authError = AstraError.auth("Sign in with Apple failed. Please try again.")
        let viewModel = SliceViewModel(
            authRepository: StubAuthRepository(signInResult: .failure(authError)),
            closetRepository: StubClosetRepository(fetchResult: .success([])),
            outfitRepository: StubOutfitRepository(),
            appleSignIn: StubAppleSignIn(outcome: .success(AppleSignInResult(identityToken: "tok", rawNonce: "nonce"))),
            networkMonitor: StubReachability(offline: false)
        )

        await viewModel.signInWithApple()

        #expect(viewModel.authPhase == .signedOut)
        guard case .failed(let error) = viewModel.garmentsState else {
            Issue.record("Expected garmentsState to be .failed after a sign-in failure")
            return
        }
        #expect(error.category == .auth)
    }

    @Test("User cancelling the Apple sheet returns to signed out without an error")
    func cancelledSignInIsNotAnError() async {
        let viewModel = SliceViewModel(
            authRepository: StubAuthRepository(signInResult: .success(sampleSession())),
            closetRepository: StubClosetRepository(fetchResult: .success([])),
            outfitRepository: StubOutfitRepository(),
            appleSignIn: StubAppleSignIn(outcome: .failure(AstraError.cancelled)),
            networkMonitor: StubReachability(offline: false)
        )

        await viewModel.signInWithApple()

        #expect(viewModel.authPhase == .signedOut)
        #expect(viewModel.garmentsState == .empty)
    }

    @Test("Garments fetch failure surfaces as GarmentsState.failed, distinguishing offline")
    func garmentsFetchFailureIsOffline() async {
        let networkError = AstraError.network("Couldn't load your closet.")
        let userID = UUID()
        let viewModel = SliceViewModel(
            authRepository: StubAuthRepository(signInResult: .success(sampleSession(userID: userID))),
            closetRepository: StubClosetRepository(fetchResult: .failure(networkError)),
            outfitRepository: StubOutfitRepository(),
            appleSignIn: StubAppleSignIn(outcome: .success(AppleSignInResult(identityToken: "tok", rawNonce: "nonce"))),
            networkMonitor: StubReachability(offline: true)
        )

        await viewModel.signInWithApple()

        #expect(viewModel.isOffline)
        guard case .failed(let error) = viewModel.garmentsState else {
            Issue.record("Expected garmentsState to be .failed")
            return
        }
        #expect(error.category == .network)
    }

    @Test("Adding a garment rejects an empty name without calling the repository")
    func addGarmentRejectsEmptyName() async {
        let userID = UUID()
        let closet = StubClosetRepository(fetchResult: .success([]))
        let viewModel = SliceViewModel(
            authRepository: StubAuthRepository(signInResult: .success(sampleSession(userID: userID))),
            closetRepository: closet,
            outfitRepository: StubOutfitRepository(),
            appleSignIn: StubAppleSignIn(outcome: .success(AppleSignInResult(identityToken: "tok", rawNonce: "nonce"))),
            networkMonitor: StubReachability(offline: false)
        )
        await viewModel.signInWithApple()

        viewModel.draftName = "   "
        await viewModel.addGarment()

        guard case .failed = viewModel.addGarmentState else {
            Issue.record("Expected addGarmentState to be .failed for a blank name")
            return
        }
        #expect(viewModel.garmentsState == .empty)
    }

    @Test("Adding a garment succeeds and prepends the new item, clearing the draft")
    func addGarmentSucceeds() async {
        let userID = UUID()
        let created = sampleClosetItem(userID: userID, name: "Charcoal Chinos")
        let viewModel = SliceViewModel(
            authRepository: StubAuthRepository(signInResult: .success(sampleSession(userID: userID))),
            closetRepository: StubClosetRepository(fetchResult: .success([]), createResult: .success(created)),
            outfitRepository: StubOutfitRepository(),
            appleSignIn: StubAppleSignIn(outcome: .success(AppleSignInResult(identityToken: "tok", rawNonce: "nonce"))),
            networkMonitor: StubReachability(offline: false)
        )
        await viewModel.signInWithApple()

        viewModel.draftName = "Charcoal Chinos"
        viewModel.draftCategory = .bottom
        viewModel.draftPrimaryColor = "charcoal"
        await viewModel.addGarment()

        #expect(viewModel.addGarmentState == .idle)
        #expect(viewModel.draftName.isEmpty)
        #expect(viewModel.draftPrimaryColor.isEmpty)
        #expect(viewModel.garmentsState.items.contains { $0.id == created.id })
    }

    @Test("Generate outfit: idle -> generating -> loaded, resolved against local closet items")
    func generateOutfitLoadsAndResolvesItems() async {
        let userID = UUID()
        let top = sampleClosetItem(userID: userID, category: .top, name: "Navy Sweater")
        let bottom = sampleClosetItem(userID: userID, category: .bottom, name: "Grey Trousers")
        let recommendation = OutfitRecommendation(
            id: UUID(),
            name: "Smart Casual",
            reason: "A tailored top with straight trousers.",
            compatibilityScore: 80,
            itemIDs: [top.id, bottom.id],
            missingProductIDs: []
        )
        let viewModel = SliceViewModel(
            authRepository: StubAuthRepository(signInResult: .success(sampleSession(userID: userID))),
            closetRepository: StubClosetRepository(fetchResult: .success([top, bottom])),
            outfitRepository: StubOutfitRepository(generateResult: .success([recommendation])),
            appleSignIn: StubAppleSignIn(outcome: .success(AppleSignInResult(identityToken: "tok", rawNonce: "nonce"))),
            networkMonitor: StubReachability(offline: false)
        )
        await viewModel.signInWithApple()

        #expect(viewModel.outfitState == .idle)
        await viewModel.generateOutfit()

        guard case .loaded(let outfit) = viewModel.outfitState else {
            Issue.record("Expected outfitState to be .loaded")
            return
        }
        #expect(outfit.name == "Smart Casual")
        // Split out of a single #expect: chaining map + two sorted(by:) with
        // trailing closures inside the macro made the type checker give up
        // ("unable to type-check in reasonable time"). Comparing Sets is both
        // faster to check and a truer statement of intent — the assertion is
        // about membership, not ordering.
        let actualItemIDs = Set(outfit.items.map(\.id))
        let expectedItemIDs: Set<UUID> = [top.id, bottom.id]
        #expect(actualItemIDs == expectedItemIDs)
    }

    @Test("Generate outfit failure surfaces as OutfitState.failed")
    func generateOutfitFailureSurfaces() async {
        let userID = UUID()
        let serverError = AstraError.server("The server encountered an error.", statusCode: 500)
        let viewModel = SliceViewModel(
            authRepository: StubAuthRepository(signInResult: .success(sampleSession(userID: userID))),
            closetRepository: StubClosetRepository(fetchResult: .success([sampleClosetItem(userID: userID)])),
            outfitRepository: StubOutfitRepository(generateResult: .failure(serverError)),
            appleSignIn: StubAppleSignIn(outcome: .success(AppleSignInResult(identityToken: "tok", rawNonce: "nonce"))),
            networkMonitor: StubReachability(offline: false)
        )
        await viewModel.signInWithApple()
        await viewModel.generateOutfit()

        guard case .failed(let error) = viewModel.outfitState else {
            Issue.record("Expected outfitState to be .failed")
            return
        }
        #expect(error.category == .server)
    }

    @Test("A recommendation that fails to persist (outfits/outfit_items) surfaces as OutfitState.failed, never .loaded")
    func generateOutfitSurfacesPersistenceFailure() async {
        let userID = UUID()
        let top = sampleClosetItem(userID: userID)
        let recommendation = OutfitRecommendation(
            id: UUID(),
            name: "Smart Casual",
            reason: "reason",
            compatibilityScore: 80,
            itemIDs: [top.id],
            missingProductIDs: []
        )
        // Models the real-world gap this fix addresses: the Edge Function
        // returns a recommendation but never persists it, so saving it as
        // real `outfits`/`outfit_items` rows is a separate step that can
        // itself fail (e.g. offline) — that failure must not present as a
        // usable "Mark Worn" outfit.
        let viewModel = SliceViewModel(
            authRepository: StubAuthRepository(signInResult: .success(sampleSession(userID: userID))),
            closetRepository: StubClosetRepository(fetchResult: .success([top])),
            outfitRepository: StubOutfitRepository(
                generateResult: .success([recommendation]),
                saveOutfitError: AstraError.network("Couldn't save that outfit.")
            ),
            appleSignIn: StubAppleSignIn(outcome: .success(AppleSignInResult(identityToken: "tok", rawNonce: "nonce"))),
            networkMonitor: StubReachability(offline: false)
        )
        await viewModel.signInWithApple()
        await viewModel.generateOutfit()

        guard case .failed(let error) = viewModel.outfitState else {
            Issue.record("Expected outfitState to be .failed when persisting the recommendation fails")
            return
        }
        #expect(error.category == .network)
    }

    @Test("Mark worn: loaded outfit -> saving -> saved, and calls recordWear exactly once")
    func markWornSucceeds() async {
        let userID = UUID()
        let top = sampleClosetItem(userID: userID)
        let recommendation = OutfitRecommendation(
            id: UUID(),
            name: "Smart Casual",
            reason: "reason",
            compatibilityScore: 80,
            itemIDs: [top.id],
            missingProductIDs: []
        )
        let outfitRepo = StubOutfitRepository(generateResult: .success([recommendation]))
        let viewModel = SliceViewModel(
            authRepository: StubAuthRepository(signInResult: .success(sampleSession(userID: userID))),
            closetRepository: StubClosetRepository(fetchResult: .success([top])),
            outfitRepository: outfitRepo,
            appleSignIn: StubAppleSignIn(outcome: .success(AppleSignInResult(identityToken: "tok", rawNonce: "nonce"))),
            networkMonitor: StubReachability(offline: false)
        )
        await viewModel.signInWithApple()
        await viewModel.generateOutfit()

        let saveCallCount = await outfitRepo.saveOutfitCallCount
        #expect(saveCallCount == 1)

        #expect(viewModel.markWornState == .idle)
        await viewModel.markWorn()

        #expect(viewModel.markWornState == .saved)
        let callCount = await outfitRepo.recordWearCallCount
        #expect(callCount == 1)
    }

    @Test("Mark worn does nothing before an outfit has been generated")
    func markWornNoOpsWithoutOutfit() async {
        let userID = UUID()
        let outfitRepo = StubOutfitRepository()
        let viewModel = SliceViewModel(
            authRepository: StubAuthRepository(signInResult: .success(sampleSession(userID: userID))),
            closetRepository: StubClosetRepository(fetchResult: .success([])),
            outfitRepository: outfitRepo,
            appleSignIn: StubAppleSignIn(outcome: .success(AppleSignInResult(identityToken: "tok", rawNonce: "nonce"))),
            networkMonitor: StubReachability(offline: false)
        )
        await viewModel.signInWithApple()
        await viewModel.markWorn()

        #expect(viewModel.markWornState == .idle)
        let callCount = await outfitRepo.recordWearCallCount
        #expect(callCount == 0)
    }

    @Test("Sign out resets every piece of slice state")
    func signOutResetsState() async {
        let userID = UUID()
        let viewModel = SliceViewModel(
            authRepository: StubAuthRepository(signInResult: .success(sampleSession(userID: userID))),
            closetRepository: StubClosetRepository(fetchResult: .success([sampleClosetItem(userID: userID)])),
            outfitRepository: StubOutfitRepository(),
            appleSignIn: StubAppleSignIn(outcome: .success(AppleSignInResult(identityToken: "tok", rawNonce: "nonce"))),
            networkMonitor: StubReachability(offline: false)
        )
        await viewModel.signInWithApple()
        #expect(viewModel.isSignedIn)

        await viewModel.signOut()

        #expect(viewModel.authPhase == .signedOut)
        #expect(viewModel.garmentsState == .empty)
        #expect(viewModel.outfitState == .idle)
        #expect(viewModel.markWornState == .idle)
    }
}
