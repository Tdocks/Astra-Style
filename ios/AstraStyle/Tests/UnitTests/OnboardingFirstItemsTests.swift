//
//  OnboardingFirstItemsTests.swift
//  AstraStyleTests
//
//  §5.1 step 12 — "add first closet items, or skip".
//
//  The first test in this file is the Phase 2 exit criterion. Everything else
//  is about the guest cap, which is the one way this step can legitimately
//  refuse to do something — and therefore the one place a "skip is blocked"
//  regression could plausibly hide.
//

import Foundation
import Testing
@testable import AstraStyle

/// A `ClosetRepository` that fails every write, to prove a broken backend
/// still cannot trap the user on this step.
private actor FailingClosetRepository: ClosetRepository {
    func fetchItems() async throws -> [ClosetItem] { throw AstraError.network("offline") }
    func fetchItem(id: UUID) async throws -> ClosetItem { throw AstraError.network("offline") }
    func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] { [] }
    func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        throw AstraError.network("offline")
    }
    func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        throw AstraError.network("offline")
    }
    func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        throw AstraError.network("Couldn't save that item.")
    }
    func updateItem(_ item: ClosetItem) async throws -> ClosetItem { throw AstraError.network("offline") }
    func archiveItem(id: UUID) async throws { throw AstraError.network("offline") }
    func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem { throw AstraError.network("offline") }
    func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem {
        throw AstraError.network("offline")
    }
    func fetchWardrobeScore() async throws -> WardrobeScore { throw AstraError.network("offline") }
}

/// `@MainActor` because `OnboardingViewModel` and `SessionStore` both are.
@MainActor
@Suite("Onboarding — first closet items (§5.1 step 12)")
struct OnboardingFirstItemsTests {

    private func makeSessionStore(isGuest: Bool) throws -> SessionStore {
        let store = SessionStore(
            apiClient: AstraAPIClient(environment: .preview),
            supabase: AstraSupabaseClientFactory.previewClient,
            keychain: KeychainTokenStore(service: "astra.test.firstitems.\(UUID().uuidString)")
        )
        try store.adopt(
            AuthSession(
                userID: UUID(),
                accessToken: "test-token",
                refreshToken: "test-refresh",
                expiresAt: .now.addingTimeInterval(3600),
                isGuest: isGuest
            )
        )
        return store
    }

    private func makeModel(
        closetRepository: any ClosetRepository = MockClosetRepository(items: []),
        isGuest: Bool = false
    ) throws -> OnboardingViewModel {
        var draft = OnboardingDraft()
        draft.selectedIdentities = [.modernHeritage, .quietLuxury, .smartCasual]
        draft.primaryIdentity = .modernHeritage
        draft.furthestStepReached = .firstItems
        return OnboardingViewModel(
            store: InMemoryOnboardingDraftStore(),
            profileRepository: MockProfileRepository(),
            closetRepository: closetRepository,
            referenceStore: InMemoryReferenceImageStore(),
            sessionStore: try makeSessionStore(isGuest: isGuest),
            draft: draft,
            step: .firstItems
        )
    }

    /// A guest repository wired the way `AppContainer` wires it, so the cap
    /// under test is the real one rather than a re-implementation.
    private func makeGuestCloset(guestID: UUID) -> GuestClosetRepository {
        GuestClosetRepository(store: InMemoryGuestClosetStore(), currentGuestUserID: { guestID })
    }

    // MARK: The exit criterion

    @Test("Skipping the step reaches the result and finishes")
    func skippingDoesNotBlockReachingHome() async throws {
        let model = try makeModel()

        #expect(model.step == .firstItems)
        #expect(model.canAdvance)
        await model.advance()
        #expect(model.step == .result)

        await model.finish()
        #expect(model.isFinished)
    }

    @Test("A closet repository that fails every write still cannot trap the user")
    func aBrokenBackendStillLetsHimLeave() async throws {
        let model = try makeModel(closetRepository: FailingClosetRepository())

        model.newItemName = "Navy merino crewneck"
        model.newItemCategory = .top
        await model.addFirstItem()

        guard case .failed = model.addItemState else {
            Issue.record("A failed write should surface as .failed, got \(model.addItemState)")
            return
        }
        #expect(model.firstItems.isEmpty)
        // The failure is beside the form, not in front of the exit.
        #expect(model.canAdvance)
        await model.advance()
        #expect(model.step == .result)
    }

    @Test("The step is skippable and the forward button says so until something is added")
    func forwardButtonNamesTheSkip() async throws {
        let model = try makeModel()
        #expect(OnboardingStep.firstItems.isSkippable)
        #expect(model.advanceIsSkip)

        model.newItemName = "Grey flannel trousers"
        model.newItemCategory = .bottom
        await model.addFirstItem()

        #expect(!model.advanceIsSkip)
        #expect(model.advanceTitle == "Continue")
    }

    // MARK: The form

    @Test("A name and a category are required; a colour is not")
    func formRequiresNameAndCategory() async throws {
        let model = try makeModel()
        #expect(!model.canAddItem)

        model.newItemName = "   "
        model.newItemCategory = .shoes
        // Whitespace is not a name. Without the trim, a spacebar tap would
        // create an item called " ".
        #expect(!model.canAddItem)

        model.newItemName = "Brown suede derbies"
        #expect(model.canAddItem)

        await model.addFirstItem()
        let item = try #require(model.firstItems.first)
        #expect(item.name == "Brown suede derbies")
        #expect(item.category == .shoes)
        #expect(item.primaryColor == nil)
    }

    @Test("A saved item carries the colour and clears the form")
    func savingClearsTheForm() async throws {
        let model = try makeModel()
        model.newItemName = "Navy merino crewneck"
        model.newItemCategory = .top
        model.newItemColor = "  navy  "

        await model.addFirstItem()

        let item = try #require(model.firstItems.first)
        #expect(item.primaryColor == "navy")
        #expect(item.laundryState == .clean)
        #expect(item.wearCount == 0)
        #expect(model.newItemName.isEmpty)
        #expect(model.newItemCategory == nil)
        #expect(model.newItemColor.isEmpty)
        #expect(model.addItemState == .added(name: "Navy merino crewneck"))
    }

    @Test("The list shows what this step added, newest first — not the whole closet")
    func listIsThisStepsWorkOnly() async throws {
        // Seeded with a closet the user already owns. An onboarding step that
        // listed it would be a closet browser, which is P3-CLOSET-08's job.
        let model = try makeModel(closetRepository: MockClosetRepository())
        #expect(model.firstItems.isEmpty)

        for name in ["First", "Second"] {
            model.newItemName = name
            model.newItemCategory = .accessory
            await model.addFirstItem()
        }

        #expect(model.firstItems.map(\.name) == ["Second", "First"])
    }

    @Test("Removing an added item takes it back out")
    func removingAnItem() async throws {
        let model = try makeModel()
        model.newItemName = "Mistyped garmnet"
        model.newItemCategory = .top
        await model.addFirstItem()
        let item = try #require(model.firstItems.first)

        await model.removeFirstItem(item)

        #expect(model.firstItems.isEmpty)
    }

    // MARK: The guest cap (spec §6.2; ADR 0011)

    @Test("A guest is told how many are left, counting what is already stored")
    func guestAllowanceCountsExistingItems() async throws {
        let guestID = UUID()
        let closet = makeGuestCloset(guestID: guestID)
        _ = try await closet.createItem(
            ClosetItem(id: UUID(), userID: guestID, name: "Already here", category: .top), images: []
        )

        let model = try makeModel(closetRepository: closet, isGuest: true)
        await model.prepareFirstItemsStep()

        // Nine, not ten. A resumed session that restarted the count would have
        // the app disagreeing with its own repository about its own rule.
        #expect(model.guestItemsRemaining == GuestLimits.maxClosetItems - 1)
    }

    @Test("A signed-in user is shown no cap, because there isn't one")
    func signedInHasNoAllowanceLine() async throws {
        let model = try makeModel(closetRepository: MockClosetRepository())
        await model.prepareFirstItemsStep()
        #expect(model.guestItemsRemaining == nil)
    }

    @Test("The eleventh guest item fails gracefully and still does not block the step")
    func guestCapIsReachedGracefully() async throws {
        let guestID = UUID()
        let model = try makeModel(closetRepository: makeGuestCloset(guestID: guestID), isGuest: true)
        await model.prepareFirstItemsStep()

        for index in 1...GuestLimits.maxClosetItems {
            model.newItemName = "Item \(index)"
            model.newItemCategory = .top
            await model.addFirstItem()
        }
        #expect(model.firstItems.count == GuestLimits.maxClosetItems)
        #expect(model.guestItemsRemaining == 0)
        #expect(model.addItemState == .guestCapReached(limit: GuestLimits.maxClosetItems))
        // The form is closed rather than left open to a write that will be
        // refused — a control that always fails is worse than one that is off.
        model.newItemName = "Item 11"
        model.newItemCategory = .top
        #expect(!model.canAddItem)

        await model.addFirstItem()
        #expect(model.firstItems.count == GuestLimits.maxClosetItems)

        // And, still, the whole point:
        #expect(model.canAdvance)
        await model.advance()
        #expect(model.step == .result)
    }

    @Test("The cap is enforced by the repository, not only by the form")
    func capSurvivesAFormThatForgetsIt() async throws {
        let guestID = UUID()
        let closet = makeGuestCloset(guestID: guestID)
        let model = try makeModel(closetRepository: closet, isGuest: true)

        // Deliberately NOT calling `prepareFirstItemsStep()`, so the view model
        // has no allowance to check against — exactly the state a future screen
        // that forgot the call would be in. The 11th write must still be
        // refused, and the refusal must still be legible.
        for index in 1...GuestLimits.maxClosetItems + 1 {
            model.newItemName = "Item \(index)"
            model.newItemCategory = .top
            await model.addFirstItem()
        }

        #expect(model.firstItems.count == GuestLimits.maxClosetItems)
        #expect(model.addItemState == .guestCapReached(limit: GuestLimits.maxClosetItems))
    }

    @Test("Removing a guest item frees a slot and reopens the form")
    func removingFreesAGuestSlot() async throws {
        let guestID = UUID()
        let model = try makeModel(closetRepository: makeGuestCloset(guestID: guestID), isGuest: true)
        await model.prepareFirstItemsStep()

        for index in 1...GuestLimits.maxClosetItems {
            model.newItemName = "Item \(index)"
            model.newItemCategory = .top
            await model.addFirstItem()
        }
        let last = try #require(model.firstItems.first)

        await model.removeFirstItem(last)

        #expect(model.guestItemsRemaining == 1)
        #expect(model.addItemState == .idle)
        model.newItemName = "Replacement"
        model.newItemCategory = .top
        #expect(model.canAddItem)
    }
}
