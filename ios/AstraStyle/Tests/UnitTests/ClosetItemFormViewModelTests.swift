//
//  ClosetItemFormViewModelTests.swift
//  AstraStyleTests
//
//  Ticket P3-CLOSET-08 ("Implement manual add garment form"), spec §6.15
//  (the fields the item detail screen must be able to edit) and §6.2 /
//  ADR 0011 (the guest closet cap).
//
//  The ticket's two acceptance criteria are the first two suites below:
//  a garment goes in end to end with no camera anywhere in the path, and
//  name plus category block submission while everything else is genuinely
//  optional.
//
//  The third suite is the one that matters most and is not in the ticket at
//  all. Editing rebuilds a `ClosetItem`, and the naive way to do that —
//  construct a fresh value from the draft — silently resets `wear_count` to
//  zero, drops `last_worn_at`, un-archives an archived row and throws away
//  the pgvector embedding. None of that throws, none of it logs, and a wear
//  history is not recoverable once it has been overwritten. `editing…`
//  below pins every one of those columns.
//

import Foundation
import Testing
@testable import AstraStyle

// MARK: - Fixtures

/// How the stub should behave. A value type rather than a stored `Error` so
/// the stub stays `Sendable` without qualification.
private enum StubOutcome: Sendable {
    case succeed
    case guestCap(limit: Int)
    case astra(AstraError)
    /// Something that is neither of the two typed failures — the case the
    /// view model has to wrap itself.
    case unexpected
}

/// A failure that is not `AstraError` and not `GuestClosetError`, so the
/// `catch` of last resort is exercised by something real.
private struct StubUnexpectedError: Error {}

/// A hand-rolled `ClosetRepository`, rather than `Core/Mocks/MockClosetRepository`.
///
/// The mock is shared fixture used by several suites and is not this
/// suite's to reshape; what these tests need is to see the EXACT
/// `ClosetItem` the view model handed over, which means recording it.
private actor StubClosetRepository: ClosetRepository {
    private let outcome: StubOutcome
    private(set) var created: [ClosetItem] = []
    private(set) var updated: [ClosetItem] = []

    init(outcome: StubOutcome = .succeed) {
        self.outcome = outcome
    }

    func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        try check()
        created.append(item)
        // Echoes the item back the way the server does, so a test asserting
        // on what `onSaved` received is asserting on a round trip rather
        // than on the value it already had in hand.
        return item
    }

    func updateItem(_ item: ClosetItem) async throws -> ClosetItem {
        try check()
        updated.append(item)
        return item
    }

    private func check() throws {
        switch outcome {
        case .succeed: return
        case .guestCap(let limit): throw GuestClosetError.capReached(limit: limit)
        case .astra(let error): throw error
        case .unexpected: throw StubUnexpectedError()
        }
    }

    // Everything below is unreachable from the form. `analyzeItem` and
    // `batchAnalyzeItems` in particular: the ticket's first acceptance
    // criterion is that the camera never opens, and these throwing is the
    // stub's way of saying the form must never call them.
    func fetchItems() async throws -> [ClosetItem] { [] }
    func fetchItem(id: UUID) async throws -> ClosetItem { throw StubUnexpectedError() }
    func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] { [] }
    func analyzeItem(imageData: Data, imageType: ClosetImageType) async throws -> ClosetItemAnalysisResult {
        throw StubUnexpectedError()
    }
    func batchAnalyzeItems(imageDataList: [Data]) async throws -> [ClosetItemAnalysisResult] {
        throw StubUnexpectedError()
    }
    func archiveItem(id: UUID) async throws { throw StubUnexpectedError() }
    func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem { throw StubUnexpectedError() }
    func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem { throw StubUnexpectedError() }
    func fetchWardrobeScore() async throws -> WardrobeScore { throw StubUnexpectedError() }
}

/// Counts `onSaved` calls. `@MainActor` so it can be captured by the
/// `@MainActor @Sendable` callback without an unchecked conformance.
@MainActor
private final class SaveRecorder {
    private(set) var saved: [ClosetItem] = []
    func record(_ item: ClosetItem) { saved.append(item) }
}

@MainActor
@Suite("Closet item form (manual add and edit)")
struct ClosetItemFormViewModelTests {

    private static let ownerID = UUID()

    private func makeAdding(
        repository: StubClosetRepository = StubClosetRepository(),
        userID: UUID? = ClosetItemFormViewModelTests.ownerID
    ) -> ClosetItemFormViewModel {
        .adding(closetRepository: repository, currentUserID: { userID })
    }

    private func makeEditing(
        item: ClosetItem,
        repository: StubClosetRepository = StubClosetRepository()
    ) -> ClosetItemFormViewModel {
        .editing(item: item, closetRepository: repository)
    }

    /// A garment with history on it — the thing an edit must not damage.
    private func wornItem(
        wearCount: Int = 23,
        lastWornAt: Date? = Date(timeIntervalSince1970: 1_700_000_000),
        archivedAt: Date? = nil
    ) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: Self.ownerID,
            name: "Navy merino crewneck",
            brand: "Uniqlo",
            category: .top,
            subcategory: "Crewneck",
            primaryColor: "navy",
            secondaryColors: ["cream"],
            pattern: .solid,
            material: ["Merino wool"],
            size: "M",
            fit: .regular,
            condition: .good,
            seasonality: [.fall, .winter],
            formalityScore: 42,
            warmthScore: 60,
            waterResistanceScore: 10,
            purchaseDate: Date(timeIntervalSince1970: 1_600_000_000),
            pricePaid: Decimal(string: "49.90"),
            currency: "GBP",
            retailer: "Uniqlo",
            productURL: URL(string: "https://shop.example.com/crewneck"),
            wearCount: wearCount,
            lastWornAt: lastWornAt,
            laundryState: .wornOnce,
            availabilityState: .available,
            archivedAt: archivedAt,
            embedding: [0.1, 0.2, 0.3],
            createdAt: Date(timeIntervalSince1970: 1_500_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_600_000_000)
        )
    }
}

// MARK: - Acceptance criterion 1: a garment goes in without the camera

extension ClosetItemFormViewModelTests {

    @Test("A name and a category are enough to add a garment, and no image is ever passed")
    func addingNeedsNothingButNameAndCategory() async throws {
        let repository = StubClosetRepository()
        let model = makeAdding(repository: repository)

        model.name = "Brown suede derbies"
        model.category = .shoes
        #expect(model.canSubmit)

        await model.submit()

        let created = try #require(await repository.created.first)
        #expect(created.name == "Brown suede derbies")
        #expect(created.category == .shoes)
        #expect(created.userID == Self.ownerID)
        // Every optional field is genuinely optional: nothing was invented
        // to fill a column, and `primary_color` in particular is nullable
        // precisely so "Grandad's watch" doesn't need a colour made up for it.
        #expect(created.brand == nil)
        #expect(created.subcategory == nil)
        #expect(created.primaryColor == nil)
        #expect(created.size == nil)
        #expect(created.fit == nil)
        #expect(created.condition == nil)
        #expect(created.pattern == nil)
        #expect(created.pricePaid == nil)
        #expect(created.currency == nil)
        #expect(created.retailer == nil)
        #expect(created.productURL == nil)
        #expect(created.secondaryColors.isEmpty)
        #expect(created.material.isEmpty)
        #expect(created.seasonality.isEmpty)
        // What "I own this" means on the day you say it.
        #expect(created.wearCount == 0)
        #expect(created.lastWornAt == nil)
        #expect(created.laundryState == .clean)
        #expect(created.availabilityState == .available)
        #expect(created.archivedAt == nil)
    }

    @Test("A full add carries every field the form collects into the created row")
    func addingRoundTripsEveryField() async throws {
        let repository = StubClosetRepository()
        let model = makeAdding(repository: repository)

        model.name = "  Charcoal flannel trousers  "
        model.brand = "Drake's"
        model.category = .bottom
        model.subcategory = "Trousers"
        model.primaryColor = "charcoal"
        model.size = "32R"
        model.fit = .tailored
        model.condition = .likeNew
        model.pattern = .check
        model.addSecondaryColor("Grey")
        model.toggleMaterial("Wool")
        model.toggleSeason(.winter)
        model.toggleSeason(.fall)
        model.laundryState = .wornOnce
        model.availabilityState = .inAlteration
        model.purchaseDate = Date(timeIntervalSince1970: 1_650_000_000)
        model.pricePaid = Decimal(string: "185")
        model.currency = "GBP"
        model.retailer = "Drake's, Savile Row"
        model.productURLText = "shop.example.com/flannels"

        await model.submit()

        let created = try #require(await repository.created.first)
        // Trimmed, not stored with the spaces the user could not see.
        #expect(created.name == "Charcoal flannel trousers")
        #expect(created.brand == "Drake's")
        #expect(created.category == .bottom)
        #expect(created.subcategory == "Trousers")
        #expect(created.primaryColor == "charcoal")
        #expect(created.size == "32R")
        #expect(created.fit == .tailored)
        #expect(created.condition == .likeNew)
        #expect(created.pattern == .check)
        #expect(created.secondaryColors == ["Grey"])
        #expect(created.material == ["Wool"])
        #expect(created.seasonality == [.winter, .fall])
        #expect(created.laundryState == .wornOnce)
        #expect(created.availabilityState == .inAlteration)
        #expect(created.purchaseDate == Date(timeIntervalSince1970: 1_650_000_000))
        #expect(created.pricePaid == Decimal(string: "185"))
        #expect(created.currency == "GBP")
        #expect(created.retailer == "Drake's, Savile Row")
        // A scheme-less paste is upgraded rather than dropped — that is
        // what a share-sheet paste usually looks like.
        #expect(created.productURL == URL(string: "https://shop.example.com/flannels"))
    }
}

// MARK: - Acceptance criterion 2: name and category block submission

extension ClosetItemFormViewModelTests {

    @Test("An empty form cannot be submitted, and says which field is missing rather than just greying out")
    func emptyFormIsBlockedWithAReason() async throws {
        let repository = StubClosetRepository()
        let model = makeAdding(repository: repository)

        #expect(!model.canSubmit)
        #expect(model.blockingReason != nil)

        // Disabled AND inert: a stray call from a hardware return key or a
        // VoiceOver double-tap must not write a nameless garment.
        await model.submit()
        #expect(await repository.created.isEmpty)
    }

    @Test("Three spaces is not a name — whitespace alone still blocks submission")
    func whitespaceOnlyNameIsNotAName() async throws {
        let repository = StubClosetRepository()
        let model = makeAdding(repository: repository)
        model.category = .top

        model.name = "   "
        #expect(!model.canSubmit)
        await model.submit()
        #expect(await repository.created.isEmpty)

        model.name = " Grey crewneck "
        #expect(model.canSubmit)
    }

    @Test("A category with no name, and a name with no category, are both blocked")
    func bothRequiredFieldsAreRequired() {
        let model = makeAdding()

        model.name = "Grey crewneck"
        #expect(!model.canSubmit)
        #expect(model.blockingReason != nil)

        model.name = ""
        model.category = .top
        #expect(!model.canSubmit)
        #expect(model.blockingReason != nil)

        model.name = "Grey crewneck"
        #expect(model.canSubmit)
        #expect(model.blockingReason == nil)
    }

    @Test("A product link that cannot be stored blocks submission instead of being silently dropped")
    func unstorableProductLinkIsRefusedRatherThanDiscarded() async throws {
        let repository = StubClosetRepository()
        let model = makeAdding(repository: repository)
        model.name = "Grey crewneck"
        model.category = .top

        model.productURLText = "not a link"
        #expect(model.productURLError != nil)
        #expect(!model.canSubmit)
        await model.submit()
        #expect(await repository.created.isEmpty)

        // Cleared, not corrected: "all other fields are optional" means it
        // may be left empty, and emptying it must unblock the form.
        model.productURLText = ""
        #expect(model.productURLError == nil)
        #expect(model.canSubmit)
    }
}

// MARK: - Editing must not destroy what it does not edit

extension ClosetItemFormViewModelTests {

    @Test("Editing preserves id, owner, creation date, wear count, last worn and archived state")
    func editingPreservesIdentityAndHistory() async throws {
        let original = wornItem(archivedAt: Date(timeIntervalSince1970: 1_690_000_000))
        let repository = StubClosetRepository()
        let model = makeEditing(item: original, repository: repository)

        // Change the things the form owns.
        model.name = "Navy merino jumper"
        model.condition = .fair

        await model.submit()

        let updated = try #require(await repository.updated.first)
        #expect(updated.name == "Navy merino jumper")
        #expect(updated.condition == .fair)

        // And nothing else. Each of these is its own line on purpose: a
        // single `#expect(updated == original)` would fail the moment the
        // test changed a field, which is every time.
        #expect(updated.id == original.id)
        #expect(updated.userID == original.userID)
        #expect(updated.createdAt == original.createdAt)
        #expect(updated.wearCount == original.wearCount)
        #expect(updated.lastWornAt == original.lastWornAt)
        #expect(updated.archivedAt == original.archivedAt)
        #expect(updated.embedding == original.embedding)
        // Server-derived signals the form never shows and must never guess.
        #expect(updated.formalityScore == original.formalityScore)
        #expect(updated.warmthScore == original.warmthScore)
        #expect(updated.waterResistanceScore == original.waterResistanceScore)
    }

    @Test("A wear history survives an edit — resetting wear count to zero would be unrecoverable data loss")
    func wearCountSurvivesAnEdit() async throws {
        let original = wornItem(wearCount: 23)
        let repository = StubClosetRepository()
        let model = makeEditing(item: original, repository: repository)

        model.name = "Renamed"
        await model.submit()

        let updated = try #require(await repository.updated.first)
        #expect(updated.wearCount == 23)
        #expect(updated.wearCount != 0)
    }

    @Test("Editing seeds the form from the row, so nothing has to be retyped to change one field")
    func editingSeedsEveryFieldFromTheRow() {
        let original = wornItem()
        let model = makeEditing(item: original)

        #expect(model.name == original.name)
        #expect(model.brand == "Uniqlo")
        #expect(model.category == .top)
        #expect(model.subcategory == "Crewneck")
        #expect(model.primaryColor == "navy")
        #expect(model.size == "M")
        #expect(model.fit == .regular)
        #expect(model.condition == .good)
        #expect(model.secondaryColors == ["cream"])
        #expect(model.material == ["Merino wool"])
        #expect(model.seasonality == [.fall, .winter])
        #expect(model.pricePaid == Decimal(string: "49.90"))
        #expect(model.currency == "GBP")
        #expect(model.productURLText == "https://shop.example.com/crewneck")
        // The row already carries detail fields, so the section holding
        // them starts open — a value hidden behind a closed disclosure is
        // a value the user concludes the app lost.
        #expect(model.showsMoreDetails)
    }

    @Test("An add starts with the detail section closed, because there is nothing in it to hide")
    func addingStartsCollapsed() {
        #expect(!makeAdding().showsMoreDetails)
    }

    @Test("The title and the primary button say which of the two jobs this is")
    func copyDiffersBetweenAddAndEdit() {
        let adding = makeAdding()
        let editing = makeEditing(item: wornItem())

        #expect(adding.submitTitle != editing.submitTitle)
        #expect(adding.title != editing.title)
        #expect(editing.submitTitle == "Save changes")
        #expect(adding.submitTitle == "Add garment")
    }
}

// MARK: - Price

extension ClosetItemFormViewModelTests {

    @Test("An untouched price is nil, not zero — 'he didn't say' and 'it was free' are different facts")
    func emptyPriceIsNilNotZero() async throws {
        let repository = StubClosetRepository()
        let model = makeAdding(repository: repository)
        model.name = "Grandad's watch"
        model.category = .watch

        await model.submit()

        let created = try #require(await repository.created.first)
        #expect(created.pricePaid == nil)
        #expect(created.pricePaid != 0)
        // And no currency either: a code with no amount attached says
        // "he paid an unknown number of pounds", which is worse than silence.
        #expect(created.currency == nil)
    }

    @Test("Clearing the price on an edit clears it on the row rather than leaving the old number")
    func clearingThePriceClearsTheColumn() async throws {
        let original = wornItem()
        let repository = StubClosetRepository()
        let model = makeEditing(item: original, repository: repository)
        #expect(model.pricePaid != nil)

        model.pricePaid = nil
        await model.submit()

        let updated = try #require(await repository.updated.first)
        #expect(updated.pricePaid == nil)
        #expect(updated.currency == nil)
    }
}

// MARK: - Failure

extension ClosetItemFormViewModelTests {

    @Test("The guest cap surfaces its own explanation, not a generic 'something went wrong'")
    func guestCapSurfacesItsOwnMessage() async throws {
        let limit = GuestLimits.maxClosetItems
        let repository = StubClosetRepository(outcome: .guestCap(limit: limit))
        let model = makeAdding(repository: repository)
        model.name = "The eleventh piece"
        model.category = .top

        await model.submit()

        let failure = try #require(model.failure)
        #expect(failure == .guestCapReached(limit: limit))
        // The exact sentence `GuestClosetError` defines, so a guest reads
        // the same words here as anywhere else in the app.
        #expect(failure.message == GuestClosetError.capReached(limit: limit).localizedDescription)
        #expect(failure.message.contains("\(limit)"))
        // Not retryable, so the form stops offering a submit that cannot
        // succeed — and says why instead of just greying out.
        #expect(!failure.isRecoverable)
        #expect(!model.canSubmit)
        #expect(model.blockingReason == failure.message)
    }

    @Test("The guest cap does not close the form or clear the draft")
    func capReachedDoesNotCloseTheForm() async throws {
        let repository = StubClosetRepository(outcome: .guestCap(limit: 10))
        let model = makeAdding(repository: repository)
        model.name = "The eleventh piece"
        model.category = .outerwear
        model.brand = "Barbour"

        await model.submit()

        // Onboarding closes its form at the cap because that step is one
        // screen of twelve and is designed to be easy to leave. This is a
        // first-class add path a man navigated to on purpose, and throwing
        // away what he typed would be the app punishing him for a limit he
        // could not see coming.
        #expect(model.name == "The eleventh piece")
        #expect(model.category == .outerwear)
        #expect(model.brand == "Barbour")
    }

    @Test("An AstraError is shown as written, because its message is already the copy for the user")
    func astraErrorMessageIsRenderedDirectly() async throws {
        let error = AstraError.network("Couldn't save that piece while you're offline.")
        let repository = StubClosetRepository(outcome: .astra(error))
        let model = makeAdding(repository: repository)
        model.name = "Grey crewneck"
        model.category = .top

        await model.submit()

        #expect(model.failure == .failed(error))
        #expect(model.failure?.message == "Couldn't save that piece while you're offline.")
        #expect(model.failure?.isRecoverable == true)
    }

    @Test("Anything else is wrapped as an unknown AstraError rather than reaching the screen raw")
    func unknownFailuresAreWrapped() async throws {
        let repository = StubClosetRepository(outcome: .unexpected)
        let model = makeAdding(repository: repository)
        model.name = "Grey crewneck"
        model.category = .top

        await model.submit()

        let failure = try #require(model.failure)
        guard case .failed(let error) = failure else {
            Issue.record("An unexpected error should surface as .failed, got \(failure)")
            return
        }
        #expect(error.category == .unknown)
        #expect(!error.message.isEmpty)
    }

    @Test("A failed submit leaves the whole draft intact, so nothing has to be retyped")
    func aFailedSubmitKeepsTheDraft() async throws {
        let repository = StubClosetRepository(outcome: .astra(AstraError.network("offline")))
        let model = makeAdding(repository: repository)
        model.name = "Charcoal flannel trousers"
        model.category = .bottom
        model.brand = "Drake's"
        model.size = "32R"
        model.pricePaid = Decimal(string: "185")
        model.toggleSeason(.winter)

        await model.submit()

        #expect(model.name == "Charcoal flannel trousers")
        #expect(model.category == .bottom)
        #expect(model.brand == "Drake's")
        #expect(model.size == "32R")
        #expect(model.pricePaid == Decimal(string: "185"))
        #expect(model.seasonality == [.winter])
        // And the form is live again, because a network failure is worth
        // trying twice.
        #expect(model.canSubmit)
        #expect(!model.isSubmitting)
    }

    @Test("Adding with no session says so rather than writing a garment that belongs to nobody")
    func addingWithoutAUserIsRefused() async throws {
        let repository = StubClosetRepository()
        let model = makeAdding(repository: repository, userID: nil)
        model.name = "Grey crewneck"
        model.category = .top

        await model.submit()

        #expect(await repository.created.isEmpty)
        let failure = try #require(model.failure)
        guard case .failed(let error) = failure else {
            Issue.record("A missing session should surface as .failed, got \(failure)")
            return
        }
        #expect(error.category == .auth)
    }
}

// MARK: - onSaved

extension ClosetItemFormViewModelTests {

    @Test("onSaved fires exactly once on success, carrying the row the repository returned")
    func onSavedFiresOnceWithTheSavedRow() async throws {
        let repository = StubClosetRepository()
        let model = makeAdding(repository: repository)
        let recorder = SaveRecorder()
        model.onSaved = { item in recorder.record(item) }

        model.name = "Grey crewneck"
        model.category = .top
        await model.submit()

        #expect(recorder.saved.count == 1)
        let saved = try #require(recorder.saved.first)
        #expect(saved.name == "Grey crewneck")

        // A second submit is a second garment, not a second callback for
        // the same one — the presenting surface dismisses on the first, so
        // a duplicate here would be a duplicate dismissal.
        await model.submit()
        #expect(recorder.saved.count == 2)
        #expect(await repository.created.count == 2)
    }

    @Test("onSaved never fires when the write failed, so nothing dismisses over an unsaved garment")
    func onSavedDoesNotFireOnFailure() async {
        let recorder = SaveRecorder()

        for outcome in [StubOutcome.astra(AstraError.network("offline")), .guestCap(limit: 10), .unexpected] {
            let model = makeAdding(repository: StubClosetRepository(outcome: outcome))
            model.onSaved = { item in recorder.record(item) }
            model.name = "Grey crewneck"
            model.category = .top
            await model.submit()
        }

        #expect(recorder.saved.isEmpty)
    }

    @Test("An edit reports the updated row, not the one it started from")
    func onSavedOnEditCarriesTheUpdate() async throws {
        let original = wornItem()
        let model = makeEditing(item: original)
        let recorder = SaveRecorder()
        model.onSaved = { item in recorder.record(item) }

        model.name = "Navy merino jumper"
        await model.submit()

        let saved = try #require(recorder.saved.first)
        #expect(saved.name == "Navy merino jumper")
        #expect(saved.id == original.id)
        #expect(saved.wearCount == original.wearCount)
    }
}

// MARK: - List editing

extension ClosetItemFormViewModelTests {

    @Test("The same colour cannot be added twice, whatever case it is typed in")
    func secondaryColoursAreDeduplicated() {
        let model = makeAdding()

        model.addSecondaryColor("Cream")
        model.addSecondaryColor("cream")
        model.addSecondaryColor("   ")
        #expect(model.secondaryColors == ["Cream"])

        model.removeSecondaryColor("CREAM")
        #expect(model.secondaryColors.isEmpty)
    }

    @Test("A material this build has never heard of is still offered back as a selected chip")
    func unknownMaterialsSurviveAsOptions() {
        let model = makeEditing(item: wornItem())
        model.toggleMaterial("Ramie")

        #expect(model.material.contains("Ramie"))
        #expect(model.materialOptions.contains("Ramie"))
        #expect(model.materialOptions.contains("Merino wool"))

        model.toggleMaterial("Ramie")
        #expect(!model.material.contains("Ramie"))
    }
}
