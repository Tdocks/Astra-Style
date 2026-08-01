//
//  ClosetEmptyReasonTests.swift
//  AstraStyleTests
//
//  Spec §6.14 "Closet overview", spec §21's empty-state copy, and spec
//  §22's ban on dead controls — the one method that decides which sentence
//  a man reads over an empty grid, and which button appears underneath it.
//
//  WHY A THIRD FILE RATHER THAN A THIRD SUITE. `ClosetViewModelTests.swift`
//  holds the two suites these tests belong beside, and it sits at 558
//  counted lines against a `file_length` ceiling of 560. That ceiling is a
//  real limit rather than a number to raise, so the group lands here
//  instead — with its own fixtures, which is already how every other
//  closet suite in this directory is built.
//
//  WHAT THIS PINS, AND WHY IT IS WORTH A FILE. `emptyReason(for:)` is the
//  only place in the closet that puts a SENTENCE on screen about something
//  the user cannot see for himself. A grid with nothing in it looks
//  identical whichever reason produced it, so a wrong answer here is not a
//  visible bug — it is a true-looking sentence that is false about the
//  man's own wardrobe, plus a recovery button that puts nothing back.
//  Both defects below shipped and both looked correct on screen:
//
//  1. A CATEGORY HE OWNS NOTHING IN was reported as a filter result the
//     moment any facet was on. He read that he owns pieces in each of
//     those categories but none in all of them at once, pressed Clear
//     Filters, and the grid stayed empty before finally admitting he owns
//     no shoes.
//
//  2. THE QUERY WON WHENEVER ONE EXISTED, rather than when it could
//     actually be the cause. Filtered to one house and then typing
//     "shirt" over a closet holding two shirts by other houses, he was
//     told nothing in his closet matches "shirt" — false — and Clear
//     Search then handed him back garments that are not shirts.
//
//  Each test below therefore asserts the sentence AND, where it is the
//  point, that the button that sentence comes with actually finishes the
//  job. The two fixes interact inside one category scope, and the last
//  test in this file is that interaction on its own.
//

import Foundation
import Testing
@testable import AstraStyle

@MainActor
@Suite("ClosetViewModel — which sentence an empty grid gets")
struct ClosetEmptyReasonTests {

    // MARK: - The query only wins when it could be the cause

    @Test("A query the facets have already excluded every match of is not why the grid is empty — quoting it back was false, and Clear Search handed back garments that are not shirts")
    func filtersOwnAnEmptyGridWhenTheQueryAloneWouldNotHaveEmptiedIt() async throws {
        let viewModel = makeViewModel(items: filterableCloset())
        await viewModel.onAppear()

        // Both narrowings have something to show and only the intersection
        // is empty: two garments in this closet answer "shirt", and the
        // one Aspesi piece is an overcoat.
        viewModel.filters.brands = ["aspesi"]
        viewModel.searchText = "shirt"
        #expect(viewModel.searchNarrowedItems.map(\.name) == ["Navy Oxford Shirt", "Ecru Linen Shirt"])
        #expect(viewModel.visibleItems.isEmpty)

        #expect(viewModel.emptyReason(for: nil) == .noFilterMatches)
        #expect(viewModel.emptyReason(for: nil) != .noSearchMatches(query: "shirt"))

        // And this is what the old sentence's recovery actually did: it
        // put an overcoat back on a screen that had just claimed nothing
        // in the closet matches "shirt".
        viewModel.clearSearch()
        #expect(viewModel.visibleItems.map(\.name) == ["Navy Wool Overcoat"])
    }

    @Test("With the facets on and a query that matches nothing anywhere, the query still names the empty state — the fix narrowed when it wins rather than deleting the precedence rule")
    func theQueryStillWinsWhenItGenuinelyExplainsTheEmptiness() async throws {
        let viewModel = makeViewModel(items: filterableCloset())
        await viewModel.onAppear()

        viewModel.filters.brands = ["sunspel"]
        viewModel.searchText = "  tuxedo "
        #expect(viewModel.searchNarrowedItems.isEmpty)
        #expect(viewModel.emptyReason(for: nil) == .noSearchMatches(query: "tuxedo"))
    }

    @Test("A fruitless query with no facets at all is still a fruitless query, because the new precedence test must not cost the case that was already right")
    func aFruitlessQueryWithoutFiltersIsUnchanged() async throws {
        let viewModel = makeViewModel(items: filterableCloset())
        await viewModel.onAppear()

        viewModel.searchText = "tuxedo"
        #expect(viewModel.filters.isEmpty)
        #expect(viewModel.emptyReason(for: nil) == .noSearchMatches(query: "tuxedo"))
    }

    @Test("From a grid both narrowings empty, Clear Search leaves a sentence about the facets and Clear Filters then leaves none — two steps that each plainly did something")
    func theTwoStepRecoveryEndsWithGarmentsBackOnScreen() async throws {
        let viewModel = makeViewModel(items: filterableCloset())
        await viewModel.onAppear()

        // The only Incotex garment is a pair of trousers, so this pair of
        // facets is genuinely empty on its own as well.
        viewModel.filters.categories = [.top]
        viewModel.filters.brands = ["incotex"]
        viewModel.searchText = "tuxedo"
        #expect(viewModel.emptyReason(for: nil) == .noSearchMatches(query: "tuxedo"))

        viewModel.clearSearch()
        #expect(viewModel.emptyReason(for: nil) == .noFilterMatches)

        viewModel.clearFilters()
        #expect(viewModel.emptyReason(for: nil) == nil)
        #expect(viewModel.visibleItemCount == 5)
    }

    // MARK: - A shelf that is bare is bare, whatever else is switched on

    @Test("A category holding nothing at all says so even with the facets on, because Clear Filters cannot put shoes into a closet that owns none")
    func anUnownedCategoryIsNotBlamedOnTheFilters() async throws {
        let viewModel = makeViewModel(items: filterableCloset())
        await viewModel.onAppear()

        viewModel.filters.brands = ["sunspel"]
        #expect(viewModel.emptyReason(for: .shoes) == .categoryIsEmpty(.shoes))
        #expect(viewModel.emptyReason(for: .shoes) != .noFilterMatches)

        // Pressing the button the old sentence came with changes nothing
        // about this shelf, which is what made it a dead control.
        viewModel.clearFilters()
        #expect(viewModel.emptyReason(for: .shoes) == .categoryIsEmpty(.shoes))
    }

    @Test("A category holding nothing at all says so mid-search too, because Clear Search cannot put shoes into a closet that owns none either")
    func anUnownedCategoryIsNotBlamedOnTheQuery() async throws {
        let viewModel = makeViewModel(items: filterableCloset())
        await viewModel.onAppear()

        // A query with matches elsewhere in the closet, so the sentence it
        // would have produced had a real word to quote back.
        viewModel.searchText = "navy"
        #expect(viewModel.visibleItemCount == 3)
        #expect(viewModel.emptyReason(for: .shoes) == .categoryIsEmpty(.shoes))
        #expect(viewModel.emptyReason(for: .shoes) != .noSearchMatches(query: "navy"))

        // And a query that matches nothing at all does not change the
        // answer either: the shelf is bare for its own reason.
        viewModel.searchText = "tuxedo"
        #expect(viewModel.emptyReason(for: .shoes) == .categoryIsEmpty(.shoes))
    }

    @Test("A category the man does own pieces in, emptied by the facets, is still a filter result — the new branch answers for bare shelves, not for shelves the panel has narrowed")
    func anOwnedCategoryEmptiedByFiltersIsStillAFilterResult() async throws {
        let viewModel = makeViewModel(items: filterableCloset())
        await viewModel.onAppear()

        // Three tops in this closet, none of them Incotex.
        viewModel.filters.brands = ["incotex"]
        #expect(viewModel.emptyReason(for: .top) == .noFilterMatches)
        #expect(viewModel.emptyReason(for: .top) != .categoryIsEmpty(.top))

        // Which makes Clear Filters the honest recovery here, and unlike
        // on the shoes shelf above it finishes the job.
        viewModel.clearFilters()
        #expect(viewModel.emptyReason(for: .top) == nil)
        #expect(viewModel.count(in: .top) == 3)
    }

    @Test("Inside a category the precedence question is asked of that category: a query with matches on the shelf but none past the facets is the facets' doing")
    func withinACategoryTheFiltersStillOwnAnIntersectionTheQueryDidNotEmpty() async throws {
        let viewModel = makeViewModel(items: filterableCloset())
        await viewModel.onAppear()

        // Two of the three tops answer "shirt"; neither is by Aspesi, and
        // Aspesi's only garment is not a top at all.
        viewModel.filters.brands = ["aspesi"]
        viewModel.searchText = "shirt"
        #expect(viewModel.emptyReason(for: .top) == .noFilterMatches)
    }

    // MARK: - Where the two fixes meet

    @Test("A category emptied by a query matching only garments on another shelf reports the query, because the scope the precedence test asks about is that category and not the closet")
    func anOwnedCategoryEmptiedByAQueryThatMatchesElsewhereReportsTheQuery() async throws {
        let viewModel = makeViewModel(items: filterableCloset())
        await viewModel.onAppear()

        // "overcoat" matches exactly one garment and it is outerwear, so
        // the query is fruitless within Tops and fruitful outside it.
        viewModel.searchText = "overcoat"
        #expect(viewModel.visibleItems.map(\.name) == ["Navy Wool Overcoat"])
        #expect(viewModel.count(in: .top) == 0)

        // Within Tops the query is the whole story: he owns three, and the
        // word he typed is what took them off the screen. Asking the
        // precedence question of the WHOLE closet instead would find a
        // match, fall past the query branch and past the empty filter set,
        // and call a shelf of three tops bare — which is the same false
        // sentence in the opposite direction.
        #expect(viewModel.emptyReason(for: .top) == .noSearchMatches(query: "overcoat"))
        #expect(viewModel.emptyReason(for: .top) != .categoryIsEmpty(.top))

        // So Clear Search is the honest recovery, and it puts them back.
        viewModel.clearSearch()
        #expect(viewModel.emptyReason(for: .top) == nil)
        #expect(viewModel.count(in: .top) == 3)
    }

}

// MARK: - Fixtures
//
// The same wardrobe `ClosetViewModelTests.swift`'s second suite is built
// on, restated here because those helpers are file-scoped over there — as
// every other closet suite in this directory's are. Restating a fixture is
// the cost of the `file_length` ceiling this file exists to respect, and
// it is a smaller cost than a shared fixture file that every suite would
// then be coupled to.

private func makeItem(
    id: UUID = UUID(),
    name: String,
    category: ClothingCategory = .top,
    brand: String? = nil,
    subcategory: String? = nil,
    primaryColor: String? = nil,
    secondaryColors: [String] = [],
    pricePaid: Decimal? = nil,
    currency: String? = nil,
    wearCount: Int = 0
) -> ClosetItem {
    ClosetItem(
        id: id,
        userID: UUID(),
        name: name,
        brand: brand,
        category: category,
        subcategory: subcategory,
        primaryColor: primaryColor,
        secondaryColors: secondaryColors,
        pricePaid: pricePaid,
        currency: currency,
        wearCount: wearCount
    )
}

@MainActor
private func makeViewModel(items: [ClosetItem]) -> ClosetViewModel {
    ClosetViewModel(
        closetRepository: StubClosetRepository(items: items),
        imageURLResolver: MockClosetImageURLResolver(),
        networkMonitor: StubNetworkMonitor()
    )
}

/// Three tops, one pair of trousers, one overcoat — and NOTHING in the
/// other four categories, which is what makes `.shoes` a shelf this closet
/// genuinely owns nothing on.
///
/// Chosen so that each of the four garment words used below separates the
/// scopes differently: "shirt" matches two tops and no outerwear, and
/// "overcoat" matches one outerwear piece and no top. Without that split
/// there is no way to tell "the query emptied this scope" apart from "the
/// query found nothing anywhere", which is the exact distinction the
/// precedence branch was getting wrong.
private func filterableCloset() -> [ClosetItem] {
    [
        makeItem(name: "Navy Wool Overcoat", category: .outerwear, brand: "Aspesi", subcategory: "Overcoat", primaryColor: "navy", pricePaid: 900, currency: "GBP", wearCount: 12),
        makeItem(name: "Navy Merino Crewneck", category: .top, brand: "Sunspel", subcategory: "Sweater", primaryColor: "navy", pricePaid: 120, currency: "GBP", wearCount: 5),
        makeItem(name: "Navy Oxford Shirt", category: .top, brand: "Drake's", subcategory: "Shirt", primaryColor: "navy", secondaryColors: ["white"], pricePaid: 180, currency: "GBP", wearCount: 3),
        makeItem(name: "Charcoal Flannel Trousers", category: .bottom, brand: "Incotex", subcategory: "Trousers", primaryColor: "charcoal", pricePaid: 240, currency: "GBP", wearCount: 1),
        makeItem(name: "Ecru Linen Shirt", category: .top, brand: "Sunspel", subcategory: "Shirt", primaryColor: "ecru", pricePaid: 90, currency: "GBP")
    ]
}

// MARK: - Stubs

/// Hands back a fixed closet in the order it was written and does nothing
/// else.
///
/// Deliberately not `MockClosetRepository`: that one sorts by `createdAt`,
/// and every garment in a fixture built in a single expression shares a
/// timestamp to well under the clock's resolution — so the order these
/// tests assert on would be a sort's tie-break rather than the fixture's.
private struct StubClosetRepository: ClosetRepository {
    let items: [ClosetItem]

    func fetchItems() async throws -> [ClosetItem] { items }

    func fetchItem(id: UUID) async throws -> ClosetItem {
        guard let item = items.first(where: { $0.id == id }) else {
            throw AstraError.server("That item couldn't be found.")
        }
        return item
    }

    func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] { [] }

    func uploadCapturedImage(_ data: Data) async throws -> String {
        _ = data
        return "users/test/closet/stub.jpg"
    }

    func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        throw AstraError.unimplemented("Scanning is not part of these tests.")
    }

    func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        throw AstraError.unimplemented("Scanning is not part of these tests.")
    }

    func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem { item }

    func updateItem(_ item: ClosetItem) async throws -> ClosetItem { item }

    func archiveItem(id: UUID) async throws {}

    func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem {
        try await fetchItem(id: id)
    }

    func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem {
        try await fetchItem(id: id)
    }

    func fetchWardrobeScore() async throws -> WardrobeScore {
        throw AstraError.unimplemented("Your wardrobe score isn't ready yet.")
    }
}

/// Online, always. Offline is orthogonal to every question this file asks
/// — an empty grid gets the same sentence either way — so it is pinned
/// rather than parameterised.
private struct StubNetworkMonitor: NetworkReachabilityMonitoring {
    func isOffline() async -> Bool { false }
}
