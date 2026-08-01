//
//  ClosetItemDetailViewModelTests.swift
//  AstraStyleTests
//
//  Spec §6.15 "Item detail" and its "Actions" block, which the task
//  breakdown splits into P3-CLOSET-06 (fields render, edits save) and
//  P3-CLOSET-09 (mark worn increments `wear_count` and sets
//  `last_worn_at`; archive sets `archived_at` and removes the item from
//  default closet views without deleting the row).
//
//  The repository stub is hand-rolled in this file rather than reusing
//  `Core/Mocks/MockClosetRepository`. Two reasons, and both are about what
//  these tests are for: the mock cannot be made to FAIL, and every
//  interesting assertion below is about what the screen does when a write
//  does not land — the rollback, the error, the fact that the user is not
//  ejected from a screen whose garment is still there. The stub also
//  counts calls, which is how "the action updates state without triggering
//  a full reload" is asserted at all rather than assumed.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("ClosetItemDetailViewModel — spec §6.15 item detail and actions")
@MainActor
struct ClosetItemDetailViewModelTests {

    // MARK: - Fixtures

    private func makeItem(
        id: UUID = UUID(),
        name: String = "Drake's knit polo",
        pricePaid: Decimal? = nil,
        currency: String? = nil,
        wearCount: Int = 0,
        lastWornAt: Date? = nil,
        laundryState: LaundryState = .clean
    ) -> ClosetItem {
        ClosetItem(
            id: id,
            userID: UUID(),
            name: name,
            brand: "Drake's",
            category: .top,
            subcategory: "Polo shirt",
            primaryColor: "navy",
            pricePaid: pricePaid,
            currency: currency,
            wearCount: wearCount,
            lastWornAt: lastWornAt,
            laundryState: laundryState
        )
    }

    private func makeImage(for itemID: UUID, hasCutout: Bool = true) -> ClosetItemImage {
        ClosetItemImage(
            id: UUID(),
            closetItemID: itemID,
            imageType: .front,
            storagePath: "closet/\(itemID.uuidString)-front.jpg",
            backgroundRemovedPath: hasCutout ? "closet/\(itemID.uuidString)-cutout.png" : nil,
            isPrimary: true
        )
    }

    private func makeViewModel(
        item: ClosetItem,
        repository: StubClosetRepository,
        resolver: StubImageURLResolver = StubImageURLResolver()
    ) -> ClosetItemDetailViewModel {
        ClosetItemDetailViewModel(
            itemID: item.id,
            closetRepository: repository,
            imageURLResolver: resolver,
            networkMonitor: StubNetworkMonitor(offline: false)
        )
    }

    // MARK: - Loading

    @Test("An item with no photographs loads as empty rather than failed, because every field on it is still correct and worth reading")
    func itemWithNoPhotographsLoadsEmpty() async throws {
        let item = makeItem()
        let repository = StubClosetRepository(item: item, images: [])
        let viewModel = makeViewModel(item: item, repository: repository)

        await viewModel.onAppear()

        guard case .empty(let detail) = viewModel.state else {
            Issue.record("Expected .empty for an item with no images, got \(viewModel.state)")
            return
        }
        #expect(detail.item.id == item.id)
        #expect(detail.heroImage == nil)
    }

    @Test("A failure to sign the photo URLs degrades the photographs only — every field still renders, because a Storage outage says nothing about the garment")
    func imageSigningFailureStillLoadsTheItem() async throws {
        let item = makeItem()
        let image = makeImage(for: item.id)
        let repository = StubClosetRepository(item: item, images: [image])
        let resolver = StubImageURLResolver(error: AstraError.server("Storage is unavailable."))
        let viewModel = makeViewModel(item: item, repository: repository, resolver: resolver)

        await viewModel.onAppear()

        let detail = try #require(viewModel.state.detail)
        #expect(detail.item.name == item.name)
        // The image is still listed — it exists — it just has no URL, which
        // is exactly what `AstraRemoteImage` renders as its no-photo state.
        #expect(detail.images.count == 1)
        #expect(detail.url(for: image) == nil)
    }

    @Test("The hero prefers the background-removed cutout over a raw capture flagged primary, per §6.15's separate 'normalized cutout image' field")
    func heroPrefersTheCutout() async throws {
        let item = makeItem()
        let rawPrimary = ClosetItemImage(
            id: UUID(),
            closetItemID: item.id,
            imageType: .onBody,
            storagePath: "closet/raw.jpg",
            isPrimary: true
        )
        let cutout = makeImage(for: item.id, hasCutout: true)
        let repository = StubClosetRepository(item: item, images: [rawPrimary, cutout])
        let viewModel = makeViewModel(item: item, repository: repository)

        await viewModel.onAppear()

        let detail = try #require(viewModel.state.detail)
        #expect(detail.heroImage?.id == cutout.id)
        #expect(detail.userPhotos.map(\.id) == [rawPrimary.id])
    }

    @Test("An AstraError from the repository reaches the screen verbatim, so the user reads the copy the error already carries rather than a second paraphrase of it")
    func loadFailurePreservesAnAstraError() async throws {
        let item = makeItem()
        let thrown = AstraError.auth("Please sign in again.")
        let repository = StubClosetRepository(item: item, fetchError: thrown)
        let viewModel = makeViewModel(item: item, repository: repository)

        await viewModel.onAppear()

        #expect(viewModel.state == .failed(thrown))
    }

    @Test("An error that is not an AstraError is mapped to .unknown rather than crashing or being swallowed")
    func loadFailureMapsAnUntypedError() async throws {
        let item = makeItem()
        let repository = StubClosetRepository(item: item, fetchError: StubClosetRepository.UntypedFailure())
        let viewModel = makeViewModel(item: item, repository: repository)

        await viewModel.onAppear()

        guard case .failed(let error) = viewModel.state else {
            Issue.record("Expected .failed, got \(viewModel.state)")
            return
        }
        #expect(error.category == .unknown)
        #expect(!error.message.isEmpty)
    }

    // MARK: - Mark worn (P3-CLOSET-09, first acceptance criterion)

    @Test("Mark worn increments wear_count by exactly 1 and sets last_worn_at, and folds in the row the repository returns instead of re-fetching the whole screen")
    func markWornIncrementsStampsAndDoesNotReload() async throws {
        let item = makeItem(wearCount: 3)
        let repository = StubClosetRepository(item: item, images: [makeImage(for: item.id)])
        let viewModel = makeViewModel(item: item, repository: repository)

        await viewModel.onAppear()
        let fetchesAfterLoad = await repository.fetchItemCallCount

        let wornAt = Date(timeIntervalSince1970: 1_780_000_000)
        await viewModel.markWorn(at: wornAt)

        let detail = try #require(viewModel.state.detail)
        #expect(detail.item.wearCount == 4)
        #expect(detail.item.lastWornAt == wornAt)
        // The repository also moves laundry state to "worn once"; the screen
        // shows what came back rather than what it predicted.
        #expect(detail.item.laundryState == .wornOnce)
        // No second read. A reload here would blank the screen mid-tap and
        // would make the action's latency the whole screen's latency.
        let fetchesAfterAction = await repository.fetchItemCallCount
        #expect(fetchesAfterAction == fetchesAfterLoad)
        #expect(viewModel.actionError == nil)
        #expect(!viewModel.isMarkingWorn)
    }

    @Test("A failed mark worn rolls the optimistic increment back and says why, rather than leaving a wear count on screen that the database does not have")
    func failedMarkWornRollsBack() async throws {
        let item = makeItem(wearCount: 3, lastWornAt: nil)
        let repository = StubClosetRepository(
            item: item,
            images: [makeImage(for: item.id)],
            markWornError: AstraError.network("Check your connection and try again.")
        )
        let viewModel = makeViewModel(item: item, repository: repository)

        await viewModel.onAppear()
        await viewModel.markWorn()

        let detail = try #require(viewModel.state.detail)
        #expect(detail.item.wearCount == 3)
        #expect(detail.item.lastWornAt == nil)
        let error = try #require(viewModel.actionError)
        #expect(error.category == .network)
        // The screen is still the item's screen — a failed write must not
        // replace correct content with an error page.
        #expect(viewModel.state.detail != nil)
    }

    @Test("Mark worn does nothing before the item has loaded, so a tap on a skeleton cannot write a wear against an item nobody has seen")
    func markWornIsInertBeforeLoad() async throws {
        let item = makeItem()
        let repository = StubClosetRepository(item: item)
        let viewModel = makeViewModel(item: item, repository: repository)

        await viewModel.markWorn()

        let markWornCalls = await repository.markWornCallCount
        #expect(markWornCalls == 0)
        #expect(viewModel.state == .loading)
    }

    // MARK: - Laundry state

    @Test("Setting the laundry state round-trips through the repository and lands in view state")
    func laundryStateRoundTrips() async throws {
        let item = makeItem(laundryState: .clean)
        let repository = StubClosetRepository(item: item, images: [makeImage(for: item.id)])
        let viewModel = makeViewModel(item: item, repository: repository)

        await viewModel.onAppear()
        await viewModel.setLaundryState(.laundry)

        let afterWash = try #require(viewModel.state.detail)
        #expect(afterWash.item.laundryState == .laundry)
        let recordedState = await repository.lastLaundryState
        #expect(recordedState == .laundry)

        await viewModel.setLaundryState(.clean)
        let afterReturn = try #require(viewModel.state.detail)
        #expect(afterReturn.item.laundryState == .clean)
    }

    @Test("A failed laundry write rolls back, so the row never shows a garment as washed when the write did not land")
    func failedLaundryWriteRollsBack() async throws {
        let item = makeItem(laundryState: .clean)
        let repository = StubClosetRepository(
            item: item,
            images: [makeImage(for: item.id)],
            laundryError: AstraError.server("Something went wrong.")
        )
        let viewModel = makeViewModel(item: item, repository: repository)

        await viewModel.onAppear()
        await viewModel.setLaundryState(.laundry)

        let detail = try #require(viewModel.state.detail)
        #expect(detail.item.laundryState == .clean)
        #expect(viewModel.actionError?.category == .server)
    }

    @Test("Setting the state the item already has is a no-op, so re-selecting the current value in the picker costs no round trip")
    func settingTheCurrentLaundryStateDoesNothing() async throws {
        let item = makeItem(laundryState: .clean)
        let repository = StubClosetRepository(item: item, images: [makeImage(for: item.id)])
        let viewModel = makeViewModel(item: item, repository: repository)

        await viewModel.onAppear()
        await viewModel.setLaundryState(.clean)

        let laundryCalls = await repository.laundryCallCount
        #expect(laundryCalls == 0)
    }

    // MARK: - Archive (P3-CLOSET-09, second acceptance criterion)

    @Test("A successful archive signals the screen to leave, and never fabricates an archived_at the database owns")
    func archiveSucceedsAndSignalsDismissal() async throws {
        let item = makeItem()
        let repository = StubClosetRepository(item: item, images: [makeImage(for: item.id)])
        let viewModel = makeViewModel(item: item, repository: repository)

        await viewModel.onAppear()
        await viewModel.archive()

        #expect(viewModel.didArchive)
        let archived = await repository.archivedIDs
        #expect(archived == [item.id])
        #expect(viewModel.actionError == nil)
        // The local copy is untouched: the timestamp is the server's, and
        // guessing it here would put a client clock into a database column.
        let detail = try #require(viewModel.state.detail)
        #expect(detail.item.archivedAt == nil)
    }

    @Test("A failed archive keeps the user on the screen and reports why — dismissing here would tell a man his jacket was gone when it is still there")
    func failedArchiveKeepsTheScreen() async throws {
        let item = makeItem()
        let repository = StubClosetRepository(
            item: item,
            images: [makeImage(for: item.id)],
            archiveError: AstraError.network("You're offline.")
        )
        let viewModel = makeViewModel(item: item, repository: repository)

        await viewModel.onAppear()
        await viewModel.archive()

        #expect(!viewModel.didArchive)
        #expect(viewModel.actionError?.category == .network)
        #expect(viewModel.state.detail != nil)
        #expect(!viewModel.isArchiving)
    }

    // MARK: - Editing

    @Test("A saved edit is folded into state without a second read, because the editor already handed back the row the repository persisted")
    func savedEditIsFoldedInWithoutRefetching() async throws {
        let item = makeItem(name: "Knit polo")
        let repository = StubClosetRepository(item: item, images: [makeImage(for: item.id)])
        let viewModel = makeViewModel(item: item, repository: repository)

        await viewModel.onAppear()
        let fetchesAfterLoad = await repository.fetchItemCallCount

        var edited = item
        edited.name = "Drake's navy knit polo"
        edited.pricePaid = 245
        viewModel.applyEditedItem(edited)

        let detail = try #require(viewModel.state.detail)
        #expect(detail.item.name == "Drake's navy knit polo")
        #expect(detail.item.pricePaid == 245)
        let fetchesAfterEdit = await repository.fetchItemCallCount
        #expect(fetchesAfterEdit == fetchesAfterLoad)
        // The counter the detail screen watches to close the edit sheet.
        #expect(viewModel.savedEditCount == 1)
        // Photographs are not the editor's to change and survive the fold.
        #expect(detail.images.count == 1)
    }

}

// MARK: - Derived copy
//
// A second suite rather than more methods on the first: these tests need
// no view model, no repository and no `await` at all — they are about the
// pure derivation of what the screen says — and SwiftLint's
// `type_body_length` caps a type at 280 lines regardless.

@Suite("ClosetItemDetailCopy — spec §6.15 cost per wear and empty fields")
struct ClosetItemDetailCopyTests {

    /// Fills brand, subcategory and primary colour and nothing else, so the
    /// unfilled-field count below is a number with a reason behind it.
    private func makeItem(
        pricePaid: Decimal? = nil,
        currency: String? = nil,
        wearCount: Int = 0
    ) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: UUID(),
            name: "Drake's knit polo",
            brand: "Drake's",
            category: .top,
            subcategory: "Polo shirt",
            primaryColor: "navy",
            pricePaid: pricePaid,
            currency: currency,
            wearCount: wearCount
        )
    }

    // MARK: - Cost per wear

    @Test("The two reasons cost per wear is undefined produce different copy — 'not yet worn' is a fact, 'add a price' is something the user can act on")
    func costPerWearDistinguishesItsTwoUndefinedCauses() {
        let neverWorn = makeItem(pricePaid: 245, wearCount: 0)
        let noPrice = makeItem(pricePaid: nil, wearCount: 12)

        let neverWornDisplay = ClosetItemDetailCopy.costPerWear(for: neverWorn)
        let noPriceDisplay = ClosetItemDetailCopy.costPerWear(for: noPrice)

        #expect(neverWornDisplay == .notYetWorn)
        #expect(noPriceDisplay == .noPriceOnFile)
        #expect(neverWornDisplay.text != noPriceDisplay.text)
    }

    @Test("Neither undefined case ever renders a dash, a zero amount or an infinity sign")
    func costPerWearNeverRendersAPlaceholderGlyph() {
        let banned = ["—", "-", "∞", "0", "0.00"]
        for display in [CostPerWearDisplay.notYetWorn, .noPriceOnFile] {
            for glyph in banned {
                #expect(display.text != glyph)
            }
            #expect(!display.text.contains("∞"))
        }
    }

    @Test("When both the price and the wears are missing, the copy names the price — it is the one of the two the user can supply")
    func missingPriceWinsOverMissingWears() {
        let bare = makeItem(pricePaid: nil, wearCount: 0)
        #expect(ClosetItemDetailCopy.costPerWear(for: bare) == .noPriceOnFile)
    }

    @Test("A negative price is treated as no price on file rather than as a negative cost per wear")
    func negativePriceReadsAsNoPrice() {
        let corrupt = makeItem(pricePaid: -40, wearCount: 4)
        #expect(ClosetItemDetailCopy.costPerWear(for: corrupt) == .noPriceOnFile)
    }

    @Test("A computable cost per wear is formatted in the item's own currency, not the device's")
    func costPerWearUsesTheItemsCurrency() throws {
        let item = makeItem(pricePaid: 100, currency: "GBP", wearCount: 4)
        guard case .amount(let formatted) = ClosetItemDetailCopy.costPerWear(for: item) else {
            Issue.record("Expected a computable cost per wear for £100 over 4 wears")
            return
        }
        #expect(formatted.contains("£"))
        #expect(formatted.contains("25"))
    }

    @Test("A missing currency falls back to USD rather than to the device locale, because relabelling a recorded amount would misstate what was paid")
    func missingCurrencyFallsBackToUSD() {
        #expect(ClosetItemDetailCopy.fallbackCurrencyCode == "USD")
        let item = makeItem(pricePaid: 100, currency: nil, wearCount: 4)
        guard case .amount(let formatted) = ClosetItemDetailCopy.costPerWear(for: item) else {
            Issue.record("Expected a computable cost per wear for 100 over 4 wears")
            return
        }
        #expect(formatted.contains("25"))
    }

    // MARK: - Unfilled fields

    @Test("The unfilled-detail count reflects the optional §6.15 fields that are genuinely blank, which is what keeps omitted rows from hiding an empty record")
    func unfilledDetailCountTracksBlankFields() {
        let sparse = ClosetItem(id: UUID(), userID: UUID(), name: "Unknown jacket", category: .outerwear)
        // 14 optional fields, none filled.
        #expect(ClosetItemDetailCopy.unfilledDetailCount(for: sparse) == 14)

        // The fixture fills brand, subcategory and primary colour.
        #expect(ClosetItemDetailCopy.unfilledDetailCount(for: makeItem()) == 11)
    }

    @Test("An empty string counts as unfilled, so a brand saved as whitespace-free emptiness does not read as a completed field")
    func emptyStringsCountAsUnfilled() {
        var item = makeItem()
        item.brand = ""
        #expect(ClosetItemDetailCopy.unfilledDetailCount(for: item) == 12)
    }
}

// MARK: - Stubs
//
// An `actor` rather than a `final class`: `ClosetRepository` is `Sendable`
// and deliberately NOT `@MainActor` (CLAUDE.md — repositories do I/O off
// the main actor), so a mutable class here would be exactly the data race
// Swift 6 strict concurrency is switched on to catch.

private actor StubClosetRepository: ClosetRepository {
    /// Deliberately not an `AstraError` — this is what the view model's
    /// `catch { }` fallback has to map to `.unknown`.
    struct UntypedFailure: Error {}

    private var item: ClosetItem
    private let images: [ClosetItemImage]
    private let fetchError: Error?
    private let markWornError: Error?
    private let laundryError: Error?
    private let archiveError: Error?

    private(set) var fetchItemCallCount = 0
    private(set) var markWornCallCount = 0
    private(set) var laundryCallCount = 0
    private(set) var archivedIDs: [UUID] = []
    private(set) var lastLaundryState: LaundryState?

    init(
        item: ClosetItem,
        images: [ClosetItemImage] = [],
        fetchError: Error? = nil,
        markWornError: Error? = nil,
        laundryError: Error? = nil,
        archiveError: Error? = nil
    ) {
        self.item = item
        self.images = images
        self.fetchError = fetchError
        self.markWornError = markWornError
        self.laundryError = laundryError
        self.archiveError = archiveError
    }

    func fetchItems() async throws -> [ClosetItem] {
        item.isArchived ? [] : [item]
    }

    func fetchItem(id: UUID) async throws -> ClosetItem {
        fetchItemCallCount += 1
        if let fetchError { throw fetchError }
        return item
    }

    func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] {
        if let fetchError { throw fetchError }
        return images
    }

    func analyzeItem(imageData: Data, imageType: ClosetImageType) async throws -> ClosetItemAnalysisResult {
        throw AstraError.unimplemented("Scanning isn't part of this screen.")
    }

    func batchAnalyzeItems(imageDataList: [Data]) async throws -> [ClosetItemAnalysisResult] {
        throw AstraError.unimplemented("Scanning isn't part of this screen.")
    }

    func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        self.item = item
        return item
    }

    func updateItem(_ item: ClosetItem) async throws -> ClosetItem {
        self.item = item
        return item
    }

    /// Mirrors the real contract: `Void`, so the caller has no updated row
    /// to fold in and must decide for itself how the screen leaves.
    func archiveItem(id: UUID) async throws {
        if let archiveError { throw archiveError }
        archivedIDs.append(id)
        item.archivedAt = .now
    }

    /// Mirrors `MockClosetRepository`/`LiveClosetRepository`: the wear also
    /// moves laundry state to `.wornOnce`, which is why the view model must
    /// take the returned row rather than predicting the result itself.
    func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem {
        markWornCallCount += 1
        if let markWornError { throw markWornError }
        item.wearCount += 1
        item.lastWornAt = wornAt
        item.laundryState = .wornOnce
        return item
    }

    func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem {
        laundryCallCount += 1
        if let laundryError { throw laundryError }
        lastLaundryState = state
        item.laundryState = state
        return item
    }

    func fetchWardrobeScore() async throws -> WardrobeScore {
        throw AstraError.unimplemented("Wardrobe Score isn't part of this screen.")
    }
}

private struct StubImageURLResolver: ClosetImageURLResolving {
    var urls: [String: URL] = [:]
    // `any Error & Sendable`, not `Error?`. `ClosetImageURLResolving` is
    // `Sendable` and this is a struct, so every stored property has to be
    // too — a bare `Error` existential is not. The actor above can hold a
    // plain `Error?` because its state is isolated rather than shared.
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

private struct StubNetworkMonitor: NetworkReachabilityMonitoring {
    let offline: Bool
    func isOffline() async -> Bool { offline }
}
