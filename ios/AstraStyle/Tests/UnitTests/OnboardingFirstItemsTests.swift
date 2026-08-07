//
//  OnboardingFirstItemsTests.swift
//  AstraStyleTests
//
//  §5.1 step 12 — "add first closet items, or skip".
//
//  The first test in this file is the Phase 2 exit criterion. Everything else
//  is about the free-tier cap, which is the one way this step can legitimately
//  refuse to do something — and therefore the one place a "skip is blocked"
//  regression could plausibly hide. (It used to be the guest cap; guest mode
//  was removed by ADR 0014 and the free-tier cap inherited the role.)
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
    func uploadCapturedImage(_ data: Data) async throws -> String {
        _ = data
        return "users/test/closet/stub.jpg"
    }

    func deleteCapturedImage(atPath storagePath: String) async throws { _ = storagePath }

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

    private func makeSessionStore() throws -> SessionStore {
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
                expiresAt: .now.addingTimeInterval(3600)
            )
        )
        return store
    }

    private func makeModel(
        closetRepository: any ClosetRepository = MockClosetRepository(items: [])
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
            sessionStore: try makeSessionStore(),
            draft: draft,
            step: .firstItems
        )
    }

    /// A capped repository wired the way `AppContainer` wires it, so the cap
    /// under test is the real one rather than a re-implementation.
    private func makeCappedCloset() -> FreeTierCappedClosetRepository {
        FreeTierCappedClosetRepository(
            base: MockClosetRepository(items: []),
            isEntitledToPremium: { false }
        )
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

    // MARK: The photo path
    //
    // The scanner writes the garment itself, through the same
    // `ClosetRepository` this step uses; `didScanItem` only tells the step
    // about a write it did not make. Every test here uses
    // `FailingClosetRepository`, which throws on `createItem` — so if this
    // seam ever started writing, all three would fail rather than quietly
    // creating two rows for one photograph.

    @Test("A scanned garment joins the list without a second write")
    func scannedItemIsRecordedNotRewritten() async throws {
        let model = try makeModel(closetRepository: FailingClosetRepository())
        let scanned = ClosetItem(
            id: UUID(),
            userID: UUID(),
            name: "Navy field jacket",
            category: .outerwear,
            primaryColor: "navy"
        )

        model.didScanItem(scanned)

        #expect(model.firstItems.map(\.id) == [scanned.id])
        // Named, not just "Saved" — this is how a man checks the analysis got
        // the right garment without opening it again.
        #expect(model.addItemState == .added(name: "Navy field jacket"))
    }

    @Test("A scanned garment makes the step look answered")
    func scannedItemStopsTheFooterOfferingASkip() async throws {
        let model = try makeModel(closetRepository: FailingClosetRepository())
        #expect(model.advanceIsSkip)

        model.didScanItem(
            ClosetItem(id: UUID(), userID: UUID(), name: "Brown suede derbies", category: .shoes)
        )

        // The footer's label comes from `stepHasAnyAnswer`, which reads
        // `firstItems`. Without this, a man who had just scanned a garment
        // would be offered "Skip for now" for the thing he had done.
        #expect(!model.advanceIsSkip)
        #expect(model.advanceTitle == "Continue")
    }

    @Test("A completion delivered twice lists the garment once")
    func scannedItemIsNotListedTwice() async throws {
        let model = try makeModel(closetRepository: FailingClosetRepository())
        let scanned = ClosetItem(id: UUID(), userID: UUID(), name: "Grey flannel trousers", category: .bottom)

        model.didScanItem(scanned)
        model.didScanItem(scanned)

        #expect(model.firstItems.count == 1)
    }

    @Test("Scanning still cannot trap the user on the step")
    func scanningDoesNotBlockReachingHome() async throws {
        let model = try makeModel(closetRepository: FailingClosetRepository())
        model.didScanItem(
            ClosetItem(id: UUID(), userID: UUID(), name: "Charcoal overcoat", category: .outerwear)
        )

        #expect(model.canAdvance)
        await model.advance()
        #expect(model.step == .result)
    }

    // MARK: The free-tier cap (spec §16)
    //
    // This step can refuse exactly one thing — a write past the free-tier
    // cap — so it is the only place a "skip is blocked" regression could
    // plausibly hide. The cap is 30, and nobody reaches it in their first
    // minute; these exist because the failure mode matters, not because the
    // path is common.

    @Test("Hitting the cap closes the form rather than leaving a control that always fails")
    func capIsReachedGracefully() async throws {
        let model = try makeModel(closetRepository: makeCappedCloset())
        await model.prepareFirstItemsStep()

        // One past the cap: the 31st write is the one the repository refuses,
        // so a loop that stops at 30 never reaches the state under test.
        for index in 1...(FreeTierLimits.maxClosetItems + 1) {
            model.newItemName = "Item \(index)"
            model.newItemCategory = .top
            await model.addFirstItem()
        }
        #expect(model.firstItems.count == FreeTierLimits.maxClosetItems)
        #expect(model.addItemState == .capReached(limit: FreeTierLimits.maxClosetItems))

        // A control that always fails is worse than one that is off.
        model.newItemName = "One too many"
        model.newItemCategory = .top
        #expect(!model.canAddItem)

        await model.addFirstItem()
        #expect(model.firstItems.count == FreeTierLimits.maxClosetItems)

        // And, still, the whole point:
        #expect(model.canAdvance)
        await model.advance()
        #expect(model.step == .result)
    }

    @Test("Removing an item reopens the form")
    func removingReopensTheForm() async throws {
        let model = try makeModel(closetRepository: makeCappedCloset())
        await model.prepareFirstItemsStep()

        for index in 1...(FreeTierLimits.maxClosetItems + 1) {
            model.newItemName = "Item \(index)"
            model.newItemCategory = .top
            await model.addFirstItem()
        }
        #expect(model.addItemState == .capReached(limit: FreeTierLimits.maxClosetItems))
        let last = try #require(model.firstItems.first)

        await model.removeFirstItem(last)

        #expect(model.addItemState == .idle)
        model.newItemName = "Replacement"
        model.newItemCategory = .top
        #expect(model.canAddItem)
    }
}
