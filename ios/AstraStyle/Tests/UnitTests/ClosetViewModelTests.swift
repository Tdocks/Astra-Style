//
//  ClosetViewModelTests.swift
//  AstraStyleTests
//
//  Spec §6.14 "Closet overview" — the header, the category tiles, and the
//  grid a tile leads to. Ticket P3-CLOSET-03.
//
//  What is worth pinning here is not "does it load a list". It is the four
//  things this screen gets wrong quietly if nobody checks: that the number
//  on a tile equals the number of garments behind it, that the three
//  reasons a grid can be empty stay three different reasons, that a
//  failure keeps its category so the error screen can decide whether Try
//  Again could ever work, and that a screenful of photographs costs ONE
//  signing request rather than one per tile — a regression that would look
//  identical on screen and only show up as a slow closet on a real
//  connection.
//
//  A SECOND SUITE FOLLOWS THE FIRST, for §6.14's metrics row and filter
//  panel. It is separate because it pins a different kind of thing: not
//  what this screen shows, but which array it hands to each of the two
//  pure values beside it — the one decision `ClosetFiltersTests` and
//  `ClosetMetricsTests` cannot see from where they stand. Its own header
//  says which four decisions and why each would be reversed by an edit
//  that looks like a tidy-up.
//

import Foundation
import Testing
@testable import AstraStyle

@MainActor
@Suite("ClosetViewModel — spec §6.14 closet overview")
struct ClosetViewModelTests {

    // MARK: - Category grouping and counts

    @Test("Counts every category the tiles show, because a tile whose number disagrees with the grid behind it is worse than no number at all")
    func countsPerCategoryMatchTheItemsBehindThem() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: mixedCloset()))
        await viewModel.onAppear()

        #expect(viewModel.count(in: .top) == 3)
        #expect(viewModel.count(in: .bottom) == 2)
        #expect(viewModel.count(in: .shoes) == 1)
        #expect(viewModel.count(in: .outerwear) == 0)
        #expect(viewModel.count(in: .accessory) == 0)
        #expect(viewModel.count(in: .watch) == 0)
        #expect(viewModel.count(in: .fragrance) == 0)

        for category in ClothingCategory.allCases {
            #expect(viewModel.items(in: category).count == viewModel.count(in: category))
            #expect(viewModel.items(in: category).allSatisfy { $0.category == category })
        }
    }

    @Test("The All items tile counts the same wardrobe the seven category tiles divide up")
    func allItemsCountEqualsTheSumOfTheCategories() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: mixedCloset()))
        await viewModel.onAppear()

        let summed = ClothingCategory.allCases.reduce(0) { $0 + viewModel.count(in: $1) }
        #expect(viewModel.visibleItemCount == 6)
        #expect(summed == viewModel.visibleItemCount)
    }

    // MARK: - Search

    @Test("Searches name, brand, subcategory and colour — the four things a man remembers about a piece he is looking for")
    func searchMatchesEveryFieldItClaimsTo() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: mixedCloset()))
        await viewModel.onAppear()

        viewModel.searchText = "loafers"
        #expect(viewModel.visibleItems.map(\.name) == ["Dark Brown Loafers"])

        viewModel.searchText = "Incotex"
        #expect(viewModel.visibleItems.map(\.name) == ["Stone Chinos"])

        viewModel.searchText = "jeans"
        #expect(viewModel.visibleItems.map(\.name) == ["Indigo Selvedge Jeans"])

        viewModel.searchText = "indigo"
        #expect(viewModel.visibleItems.map(\.name) == ["Indigo Selvedge Jeans"])
    }

    @Test("Search ignores case and surrounding whitespace, because a search field is typed into on a phone")
    func searchIsCaseAndWhitespaceInsensitive() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: mixedCloset()))
        await viewModel.onAppear()

        viewModel.searchText = "   MERINO  "
        #expect(viewModel.visibleItems.map(\.name) == ["Navy Merino Crewneck"])
    }

    @Test("A search narrows the category tiles too, so the number on a tile is never a different fact from the grid behind it")
    func searchNarrowsTheCategoryCountsAsWell() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: mixedCloset()))
        await viewModel.onAppear()

        viewModel.searchText = "navy"
        #expect(viewModel.count(in: .top) == 1)
        #expect(viewModel.count(in: .bottom) == 0)
        #expect(viewModel.visibleItemCount == 1)
    }

    @Test("Whitespace alone is not a search — a field the user has cleared back to spaces still shows the whole closet")
    func whitespaceOnlyQueryIsNotTreatedAsASearch() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: mixedCloset()))
        await viewModel.onAppear()

        viewModel.searchText = "   "
        #expect(viewModel.isSearching == false)
        #expect(viewModel.visibleItemCount == 6)
    }

    // MARK: - The three empty states

    @Test("An empty closet is the state the spec writes copy for, and it wins over every other scope")
    func emptyClosetReportsClosetIsEmptyWhateverTheScope() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: []))
        await viewModel.onAppear()

        #expect(viewModel.state == .empty([]))
        #expect(viewModel.emptyReason(for: nil) == .closetIsEmpty)
        #expect(viewModel.emptyReason(for: .outerwear) == .closetIsEmpty)

        // Even mid-search: a man with no clothes has not mistyped a brand.
        viewModel.searchText = "loafers"
        #expect(viewModel.emptyReason(for: nil) == .closetIsEmpty)
    }

    @Test("A category with nothing in it is its own state, not an empty closet — the wardrobe is full, this shelf is not")
    func emptyCategoryIsDistinctFromAnEmptyCloset() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: mixedCloset()))
        await viewModel.onAppear()

        #expect(viewModel.emptyReason(for: .outerwear) == .categoryIsEmpty(.outerwear))
        #expect(viewModel.emptyReason(for: .top) == nil)
        #expect(viewModel.emptyReason(for: nil) == nil)
    }

    @Test("A search that finds nothing is a third state again, and carries the query so the copy can quote it back")
    func fruitlessSearchIsDistinctFromBothEmptyStates() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: mixedCloset()))
        await viewModel.onAppear()

        viewModel.searchText = "  tuxedo "
        #expect(viewModel.emptyReason(for: nil) == .noSearchMatches(query: "tuxedo"))
        // Inside a category that does have garments, a fruitless search is
        // still a fruitless search rather than an empty category.
        #expect(viewModel.emptyReason(for: .top) == .noSearchMatches(query: "tuxedo"))

        viewModel.clearSearch()
        #expect(viewModel.emptyReason(for: nil) == nil)
    }

    @Test("Nothing is empty while the closet is still loading or has failed — an empty state over an unknown closet is a guess")
    func noEmptyReasonBeforeTheClosetIsKnown() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(itemsError: AstraError.network("Offline.")))
        #expect(viewModel.emptyReason(for: nil) == nil)

        await viewModel.onAppear()
        #expect(viewModel.emptyReason(for: nil) == nil)
        #expect(viewModel.emptyReason(for: .top) == nil)
    }

    // MARK: - Error mapping

    @Test("A typed repository failure keeps its category, so the error screen can tell a retryable outage from a capability that does not exist")
    func typedErrorsSurviveIntact() async throws {
        let failure = AstraError.network("Couldn't load your closet.")
        let viewModel = makeViewModel(repository: StubClosetRepository(itemsError: failure))
        await viewModel.onAppear()

        guard case .failed(let error) = viewModel.state else {
            Issue.record("Expected .failed, got \(viewModel.state)")
            return
        }
        #expect(error == failure)
        #expect(error.isRetryable)
    }

    @Test("An unimplemented capability stays unimplemented rather than being flattened into a server error, because only one of the two grows a Try Again button")
    func unimplementedIsNotFlattenedIntoAGenericFailure() async throws {
        let failure = AstraError.unimplemented("This part of your closet isn't ready yet.")
        let viewModel = makeViewModel(repository: StubClosetRepository(itemsError: failure))
        await viewModel.onAppear()

        guard case .failed(let error) = viewModel.state else {
            Issue.record("Expected .failed, got \(viewModel.state)")
            return
        }
        #expect(error.category == .unimplemented)
        #expect(error.isRetryable == false)
    }

    @Test("A failure that is not an AstraError is still surfaced, as unknown, rather than swallowed into a blank screen")
    func untypedErrorsBecomeUnknownAstraErrors() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(itemsError: StubUnexpectedError()))
        await viewModel.onAppear()

        guard case .failed(let error) = viewModel.state else {
            Issue.record("Expected .failed, got \(viewModel.state)")
            return
        }
        #expect(error.category == .unknown)
        #expect(error.message.isEmpty == false)
    }

    // MARK: - Image resolution

    @Test("A screenful of tiles costs exactly one signing request, not one per garment — the whole reason the batch method exists")
    func aScreenfulOfTilesIsOneBatchNotNRequests() async throws {
        let items = mixedCloset()
        let repository = StubClosetRepository(items: items, imagesByItemID: primaryImages(for: items))
        let resolver = CountingImageURLResolver()
        let viewModel = makeViewModel(repository: repository, resolver: resolver)
        await viewModel.onAppear()

        for item in items {
            viewModel.imageNeeded(for: item)
        }
        await viewModel.awaitPendingImageResolution()

        let batchCallCount = await resolver.batchCallCount
        let singleCallCount = await resolver.singleCallCount
        let batchedPathCount = await resolver.lastBatchPathCount
        #expect(batchCallCount == 1)
        #expect(singleCallCount == 0)
        #expect(batchedPathCount == items.count)

        // And every tile actually got a URL out of that one request.
        for item in items {
            _ = try #require(viewModel.imageURL(for: item), "No image URL resolved for \(item.name)")
        }
    }

    @Test("Garments with no photograph cost no signing request at all, rather than one that signs nothing")
    func garmentsWithoutPhotographsDoNotTriggerASigningRequest() async throws {
        let items = mixedCloset()
        let repository = StubClosetRepository(items: items)
        let resolver = CountingImageURLResolver()
        let viewModel = makeViewModel(repository: repository, resolver: resolver)
        await viewModel.onAppear()

        for item in items {
            viewModel.imageNeeded(for: item)
        }
        await viewModel.awaitPendingImageResolution()

        let batchCallCount = await resolver.batchCallCount
        #expect(batchCallCount == 0)
        #expect(viewModel.imageURL(for: items[0]) == nil)
    }

    @Test("Scrolling back over tiles already resolved does not sign them again")
    func alreadyResolvedTilesAreNotResolvedTwice() async throws {
        let items = mixedCloset()
        let repository = StubClosetRepository(items: items, imagesByItemID: primaryImages(for: items))
        let resolver = CountingImageURLResolver()
        let viewModel = makeViewModel(repository: repository, resolver: resolver)
        await viewModel.onAppear()

        for item in items {
            viewModel.imageNeeded(for: item)
        }
        await viewModel.awaitPendingImageResolution()

        for item in items {
            viewModel.imageNeeded(for: item)
        }
        await viewModel.awaitPendingImageResolution()

        let batchCallCount = await resolver.batchCallCount
        let fetchImagesCallCount = await repository.fetchImagesCallCount
        #expect(batchCallCount == 1)
        #expect(fetchImagesCallCount == items.count)
    }

    @Test("Signing failing leaves the garments on screen — the photographs are a module, the closet is the screen")
    func failedSigningDoesNotReplaceTheClosetWithAnError() async throws {
        let items = mixedCloset()
        let repository = StubClosetRepository(items: items, imagesByItemID: primaryImages(for: items))
        let resolver = CountingImageURLResolver(shouldFailBatch: true)
        let viewModel = makeViewModel(repository: repository, resolver: resolver)
        await viewModel.onAppear()

        for item in items {
            viewModel.imageNeeded(for: item)
        }
        await viewModel.awaitPendingImageResolution()

        #expect(viewModel.state == .loaded(items))
        #expect(viewModel.visibleItemCount == items.count)
        #expect(viewModel.imageURL(for: items[0]) == nil)
    }

    // MARK: - Offline, lifecycle, and what is deliberately not called

    @Test("Offline is tracked beside the content state, not instead of it, so a cached closet stays viewable")
    func offlineIsOrthogonalToTheContentState() async throws {
        let items = mixedCloset()
        let viewModel = makeViewModel(repository: StubClosetRepository(items: items), isOffline: true)
        await viewModel.onAppear()

        #expect(viewModel.isOffline)
        #expect(viewModel.state == .loaded(items))
        #expect(viewModel.state.showsOfflineBannerWhenStale)
    }

    @Test("A second appearance does not refetch, because returning to a tab is not a request to reload it")
    func onAppearLoadsOnceAndRefreshReloads() async throws {
        let repository = StubClosetRepository(items: mixedCloset())
        let viewModel = makeViewModel(repository: repository)

        await viewModel.onAppear()
        await viewModel.onAppear()
        let afterTwoAppearances = await repository.fetchItemsCallCount
        #expect(afterTwoAppearances == 1)

        await viewModel.refresh()
        let afterRefresh = await repository.fetchItemsCallCount
        #expect(afterRefresh == 2)
    }

    @Test("Pull to refresh keeps the garments on screen instead of dropping back to the skeleton under its own spinner")
    func refreshDoesNotReturnToTheLoadingState() async throws {
        let items = mixedCloset()
        let viewModel = makeViewModel(repository: StubClosetRepository(items: items))
        await viewModel.onAppear()

        await viewModel.refresh()
        #expect(viewModel.state == .loaded(items))
        #expect(viewModel.isRefreshing == false)
    }

    @Test("The search field is only offered over a closet it could narrow, so it is never a control that cannot do anything")
    func searchIsOnlyOfferedWhenThereIsSomethingToSearch() async throws {
        let loading = makeViewModel(repository: StubClosetRepository(items: mixedCloset()))
        #expect(loading.state.hasSearchableContent == false)

        await loading.onAppear()
        #expect(loading.state.hasSearchableContent)

        let emptyCloset = makeViewModel(repository: StubClosetRepository(items: []))
        await emptyCloset.onAppear()
        #expect(emptyCloset.state.hasSearchableContent == false)

        let failing = makeViewModel(repository: StubClosetRepository(itemsError: AstraError.network("Offline.")))
        await failing.onAppear()
        #expect(failing.state.hasSearchableContent == false)
    }

    @Test("The wardrobe score is never requested, because the endpoint behind it cannot succeed and a permanent error is not a metric")
    func theWardrobeScoreEndpointIsNeverCalled() async throws {
        let repository = StubClosetRepository(items: mixedCloset())
        let viewModel = makeViewModel(repository: repository)

        await viewModel.onAppear()
        await viewModel.refresh()

        let wardrobeScoreCallCount = await repository.fetchWardrobeScoreCallCount
        #expect(wardrobeScoreCallCount == 0)
    }

}

// MARK: - The §6.14 integration: metrics, filter panel, and the search seam
//
// The pieces underneath this screen already have suites of their own:
// `ClosetFiltersTests` proves `apply(to:)` narrows an array the way the
// eight facets say, and `ClosetMetricsTests` proves `compute(for:)` adds
// prices up without inventing a currency. Neither can prove the only thing
// this view model actually decides — WHICH array each of them is handed —
// and four such decisions currently live nowhere but a comment.
//
// Each of them is the kind a later edit reverses while making the code
// look MORE consistent, which is exactly the sort a comment does not
// survive: deriving the panel's chips from `visibleItems` "so the panel
// agrees with the grid", or computing the metrics over `visibleItems` "so
// the numbers agree with the tiles". Both are one word's difference in the
// source and neither shows up as a crash.
//
// A second suite rather than more tests in the one above: that one is
// about the tiles and the images, this one is about how three narrowings
// compose. `type_body_length` and `file_length` are both real ceilings
// here rather than numbers to raise, which is why each test below carries
// one behaviour and no ceremony — the file sits close enough to the
// 560-line limit that a redundant assertion costs something.

@MainActor
@Suite("ClosetViewModel — spec §6.14 metrics, filters, and the search seam")
struct ClosetViewModelFilterIntegrationTests {

    // MARK: - The scope the filter panel is built from

    @Test("The panel's scope answers the search field and nothing else, because a scope the user's own taps can move deletes chips from under the finger tapping them")
    func searchNarrowedItemsIgnoreTheActiveFilters() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: filterableCloset()))
        await viewModel.onAppear()

        #expect(viewModel.searchNarrowedItems.count == 5)

        // A filter set that visibly moves the grid: two of the five
        // garments carry this brand, so if the panel's scope were
        // filter-aware this count would drop to two.
        viewModel.filters.brands = ["sunspel"]
        #expect(viewModel.visibleItems.map(\.name) == ["Navy Merino Crewneck", "Ecru Linen Shirt"])
        #expect(viewModel.searchNarrowedItems.count == 5)

        viewModel.searchText = "navy"
        #expect(viewModel.searchNarrowedItems.map(\.name) == ["Navy Wool Overcoat", "Navy Merino Crewneck", "Navy Oxford Shirt"])
        #expect(viewModel.visibleItems.map(\.name) == ["Navy Merino Crewneck"])

        // And it does follow the query, which is the half that must stay
        // live: the field is behind the sheet, so it can only change
        // between openings.
        viewModel.clearFilters()
        #expect(viewModel.searchNarrowedItems.count == 3)

        // The panel's "Show N items" is this same scope with the pending
        // facets applied — literally the closure `ClosetView` hands
        // `ClosetFilterPanelView` — so the number on its button is the
        // number of garments the grid will hold when the sheet closes.
        viewModel.filters.categories = [.top]
        #expect(viewModel.filters.apply(to: viewModel.searchNarrowedItems).count == viewModel.visibleItemCount)
        #expect(viewModel.visibleItemCount == 2)
    }

    @Test("The offered chips are derived from the search-narrowed, filter-free closet, so choosing one facet never changes which chips are on offer")
    func filterOptionsAreDerivedFromTheSearchNarrowedFilterFreeCloset() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: filterableCloset()))
        await viewModel.onAppear()

        viewModel.searchText = "navy"
        let offered = viewModel.filterOptions

        // Search-narrowed: Incotex is on the charcoal trousers, which the
        // query has already excluded, so that chip is not offered — and
        // the two wear bands offered are the two the navy pieces occupy.
        #expect(offered.brands.map(\.displayName) == ["Aspesi", "Drake's", "Sunspel"])
        #expect(offered.wearCounts == [.threeToNine, .tenOrMore])

        // Filter-free: choosing a brand leaves every chip where it was.
        // Derived from `visibleItems` instead, the brand facet would
        // collapse to the single value now covering the whole scope and be
        // dropped altogether as a facet that cannot narrow.
        viewModel.filters.brands = ["sunspel"]
        #expect(viewModel.filterOptions == offered)

        // Including when the combination matches nothing at all, which is
        // the point at which a filter-aware panel would be empty.
        viewModel.filters.wearCounts = [.tenOrMore]
        #expect(viewModel.visibleItems.isEmpty)
        #expect(viewModel.filterOptions == offered)
    }

    // MARK: - The grid is both narrowings at once

    @Test("The grid is the intersection of the query and the facets, because a man who types a word with a filter on is asking for both at once")
    func visibleItemsComposeSearchAndFilters() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: filterableCloset()))
        await viewModel.onAppear()

        viewModel.filters.colors = ["navy"]
        #expect(viewModel.visibleItems.count == 3)
        #expect(viewModel.count(in: .top) == 2)
        #expect(viewModel.count(in: .bottom) == 0)

        // Two garments answer the query, three answer the facet, and one
        // answers both — so an intersection is a strict subset of either
        // half and a union would be four.
        viewModel.searchText = "shirt"
        #expect(viewModel.searchNarrowedItems.count == 2)
        #expect(viewModel.visibleItems.map(\.name) == ["Navy Oxford Shirt"])
        #expect(viewModel.count(in: .top) == 1)
        #expect(viewModel.visibleItems.allSatisfy { viewModel.searchNarrowedItems.contains($0) })
    }

    // MARK: - Metrics are about the wardrobe, not about the scope

    @Test("Neither a query nor a facet moves the metrics, because a total that falls when three letters are typed reads as money going missing rather than as a filter working")
    func metricsAreInvariantToBothNarrowings() async throws {
        let items = filterableCloset()
        let viewModel = makeViewModel(repository: StubClosetRepository(items: items))
        await viewModel.onAppear()

        let wholeCloset = viewModel.metrics
        let overcoat = try #require(items.first { $0.name == "Navy Wool Overcoat" })
        let subtotal = try #require(wholeCloset.estimatedValue.subtotals.first)
        #expect(wholeCloset.totalItems == 5)
        #expect(subtotal.amount == 1530)
        #expect(wholeCloset.estimatedValue.isComplete)
        #expect(wholeCloset.mostWorn.selectableItemID == overcoat.id)

        viewModel.searchText = "navy"
        #expect(viewModel.visibleItemCount == 3)
        #expect(viewModel.metrics == wholeCloset)

        viewModel.filters.brands = ["sunspel"]
        #expect(viewModel.visibleItemCount == 1)
        #expect(viewModel.metrics == wholeCloset)

        // The counts on the category tiles beside them DO follow both, and
        // that difference is the decision: a tile is a door and its number
        // has to be the number of garments behind it, where "estimated
        // closet value" is a statement about the closet.
        #expect(viewModel.count(in: .top) == 1)
    }

    @Test("A garment added while a search is running still counts towards the metrics, because it is genuinely in the closet even though the query is genuinely hiding it")
    func metricsFollowTheClosetItselfWhenAnItemIsAdded() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: filterableCloset()))
        await viewModel.onAppear()

        viewModel.searchText = "navy"
        let beforeAdding = viewModel.metrics
        #expect(viewModel.visibleItemCount == 3)

        viewModel.insertSavedItem(makeItem(name: "Tan Suede Boots", category: .shoes, brand: "Crockett & Jones", primaryColor: "tan", pricePaid: 400, currency: "GBP"))

        let afterAdding = viewModel.metrics
        let subtotal = try #require(afterAdding.estimatedValue.subtotals.first)
        #expect(afterAdding != beforeAdding)
        #expect(afterAdding.totalItems == 6)
        #expect(subtotal.amount == 1930)
        // The grid does not move, because the boots are not navy.
        #expect(viewModel.visibleItemCount == 3)
    }

    // MARK: - The fourth reason a grid can be empty

    @Test("A filter set that excludes everything says so, because before this reason existed the screen drew a blank grid with no sentence on it")
    func filtersThatMatchNothingHaveTheirOwnEmptyReason() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: filterableCloset()))
        await viewModel.onAppear()
        #expect(viewModel.emptyReason(for: nil) == nil)

        // Both chips are offered by this closet — it has tops and it has
        // an Incotex garment, just not one that is both — which is the
        // combination `ClosetFilterOptions` says the panel cannot rule out.
        viewModel.filters.categories = [.top]
        viewModel.filters.brands = ["incotex"]
        #expect(viewModel.emptyReason(for: nil) == .noFilterMatches)

        viewModel.clearFilters()
        #expect(viewModel.emptyReason(for: nil) == nil)
    }

    @Test("With a query and a filter set both active the query names the empty state, and clearing it hands the screen to the filters rather than to nothing at all")
    func searchOutranksFiltersAndClearingItRevealsTheFilterReason() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: filterableCloset()))
        await viewModel.onAppear()

        viewModel.filters.categories = [.top]
        viewModel.filters.brands = ["incotex"]
        viewModel.searchText = "  tuxedo "

        // Both narrowings could explain this grid. The query wins because
        // its sentence can quote the typo back, which no sentence about
        // eight facets can do.
        #expect(viewModel.emptyReason(for: nil) == .noSearchMatches(query: "tuxedo"))

        // And the recovery it offers is not a dead control when it does
        // not finish the job: the sentence changes and grows its own Clear
        // Filters, rather than the same screen coming back.
        viewModel.clearSearch()
        #expect(viewModel.isSearching == false)
        #expect(viewModel.emptyReason(for: nil) == .noFilterMatches)

        viewModel.clearFilters()
        #expect(viewModel.emptyReason(for: nil) == nil)
    }

    @Test("A category emptied by the filters is a filter result rather than an empty shelf, because the closet does have tops and clearing the filters brings them back")
    func categoryScopedEmptyReasonSeparatesFiltersFromAnEmptyCategory() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: filterableCloset()))
        await viewModel.onAppear()

        #expect(viewModel.emptyReason(for: .shoes) == .categoryIsEmpty(.shoes))
        #expect(viewModel.emptyReason(for: .top) == nil)

        // The only Incotex garment is a pair of trousers.
        viewModel.filters.brands = ["incotex"]
        #expect(viewModel.emptyReason(for: .top) == .noFilterMatches)
        // The whole-closet grid still has the trousers in it, so it is not
        // empty and has no reason to give.
        #expect(viewModel.emptyReason(for: nil) == nil)

        viewModel.clearFilters()
        #expect(viewModel.count(in: .top) == 3)
    }

    // MARK: - Two controls, cleared separately

    @Test("Each control clears only itself, so a man who has just been shown a sentence about one narrowing can tell which of the two put his garments back")
    func clearingEitherControlLeavesTheOtherStanding() async throws {
        let viewModel = makeViewModel(repository: StubClosetRepository(items: filterableCloset()))
        await viewModel.onAppear()

        viewModel.searchText = "navy"
        viewModel.filters.brands = ["sunspel"]
        #expect(viewModel.visibleItemCount == 1)

        // Clear Filters restores the unfiltered view without touching a
        // query the user did not ask to undo.
        viewModel.clearFilters()
        #expect(viewModel.filters.isEmpty)
        #expect(viewModel.searchText == "navy")
        #expect(viewModel.visibleItemCount == 3)

        // And the mirror: emptying the field leaves the facets exactly
        // where the panel left them.
        viewModel.filters.brands = ["sunspel"]
        viewModel.clearSearch()
        #expect(viewModel.isSearching == false)
        #expect(viewModel.filters.brands == ["sunspel"])
        #expect(viewModel.visibleItems.map(\.name) == ["Navy Merino Crewneck", "Ecru Linen Shirt"])
    }

}

// MARK: - Fixtures
//
// At file scope rather than on the suite: they are shared by every test,
// none of them touches suite state, and a suite whose body is mostly
// fixtures stops reading as a list of behaviours.

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
private func makeViewModel(
    repository: StubClosetRepository,
    resolver: CountingImageURLResolver = CountingImageURLResolver(),
    isOffline: Bool = false
) -> ClosetViewModel {
    ClosetViewModel(
        closetRepository: repository,
        imageURLResolver: resolver,
        networkMonitor: StubNetworkMonitor(offline: isOffline)
    )
}

/// A wardrobe with a known shape: 3 tops, 2 bottoms, 1 pair of shoes, and
/// nothing at all in the other four categories.
private func mixedCloset() -> [ClosetItem] {
    [
        makeItem(name: "Navy Merino Crewneck", category: .top, brand: "Sunspel", subcategory: "Sweater", primaryColor: "navy"),
        makeItem(name: "White Oxford Shirt", category: .top, brand: "Drake's", subcategory: "Shirt", primaryColor: "white"),
        makeItem(name: "Grey Marl Tee", category: .top, subcategory: "T-shirt", primaryColor: "grey"),
        makeItem(name: "Stone Chinos", category: .bottom, brand: "Incotex", subcategory: "Trousers", primaryColor: "stone"),
        makeItem(name: "Indigo Selvedge Jeans", category: .bottom, subcategory: "Jeans", primaryColor: "indigo"),
        makeItem(name: "Dark Brown Loafers", category: .shoes, brand: "Crockett & Jones", primaryColor: "brown")
    ]
}

/// A wardrobe built for the search/filter/metrics seam rather than for the
/// tiles: three navy pieces spread across two categories, one charcoal
/// piece the word "navy" excludes, four brands, and a price and a wear
/// count on every garment so the metrics row has something to be invariant
/// about.
///
/// Every facet used below is one the panel would actually offer for this
/// closet — a filter combination a test can only reach by hand proves
/// nothing about a control the user can reach.
private func filterableCloset() -> [ClosetItem] {
    [
        makeItem(name: "Navy Wool Overcoat", category: .outerwear, brand: "Aspesi", subcategory: "Overcoat", primaryColor: "navy", pricePaid: 900, currency: "GBP", wearCount: 12),
        makeItem(name: "Navy Merino Crewneck", category: .top, brand: "Sunspel", subcategory: "Sweater", primaryColor: "navy", pricePaid: 120, currency: "GBP", wearCount: 5),
        makeItem(name: "Navy Oxford Shirt", category: .top, brand: "Drake's", subcategory: "Shirt", primaryColor: "navy", secondaryColors: ["white"], pricePaid: 180, currency: "GBP", wearCount: 3),
        makeItem(name: "Charcoal Flannel Trousers", category: .bottom, brand: "Incotex", subcategory: "Trousers", primaryColor: "charcoal", pricePaid: 240, currency: "GBP", wearCount: 1),
        makeItem(name: "Ecru Linen Shirt", category: .top, brand: "Sunspel", subcategory: "Shirt", primaryColor: "ecru", pricePaid: 90, currency: "GBP")
    ]
}

/// One primary photograph per garment, so a test can tell "no photograph
/// to sign" apart from "photographs signed in one request".
private func primaryImages(for items: [ClosetItem]) -> [UUID: [ClosetItemImage]] {
    items.reduce(into: [:]) { result, item in
        result[item.id] = [
            ClosetItemImage(
                id: UUID(),
                closetItemID: item.id,
                imageType: .front,
                storagePath: "closet/\(item.id.uuidString.lowercased())-front.jpg",
                isPrimary: true
            )
        ]
    }
}

// MARK: - Stubs

/// Deliberately not `MockClosetRepository`: these tests need to count
/// calls, to fail on demand, and to hand back a known set of images per
/// item. Counting is what proves the batch behaviour, and a shared preview
/// mock that grew counters would carry them into every other suite.
private actor StubClosetRepository: ClosetRepository {
    private let items: [ClosetItem]
    private let itemsError: Error?
    private let imagesByItemID: [UUID: [ClosetItemImage]]

    private(set) var fetchItemsCallCount = 0
    private(set) var fetchImagesCallCount = 0
    private(set) var fetchWardrobeScoreCallCount = 0

    init(
        items: [ClosetItem] = [],
        itemsError: Error? = nil,
        imagesByItemID: [UUID: [ClosetItemImage]] = [:]
    ) {
        self.items = items
        self.itemsError = itemsError
        self.imagesByItemID = imagesByItemID
    }

    func fetchItems() async throws -> [ClosetItem] {
        fetchItemsCallCount += 1
        if let itemsError { throw itemsError }
        return items
    }

    func fetchItem(id: UUID) async throws -> ClosetItem {
        guard let item = items.first(where: { $0.id == id }) else {
            throw AstraError.server("That item couldn't be found.")
        }
        return item
    }

    func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] {
        fetchImagesCallCount += 1
        return imagesByItemID[itemID] ?? []
    }

    func uploadCapturedImage(_ data: Data) async throws -> String {
        _ = data; return "users/test/closet/stub.jpg"
    }

    func deleteCapturedImage(atPath storagePath: String) async throws { _ = storagePath }
    func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        throw AstraError.unimplemented("Scanning is not part of this screen.")
    }
    func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        throw AstraError.unimplemented("Scanning is not part of this screen.")
    }
    func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem { item }
    func updateItem(_ item: ClosetItem) async throws -> ClosetItem { item }
    func archiveItem(id: UUID) async throws {}
    func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem { try await fetchItem(id: id) }
    func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem { try await fetchItem(id: id) }

    /// Throws the way the live repository throws today, and counts the
    /// call so a test can assert the closet overview never makes it.
    func fetchWardrobeScore() async throws -> WardrobeScore {
        fetchWardrobeScoreCallCount += 1
        throw AstraError.unimplemented("Your wardrobe score isn't ready yet.")
    }
}

/// Counts single versus batch resolution so "one request for a screenful"
/// is an assertion rather than an intention.
private actor CountingImageURLResolver: ClosetImageURLResolving {
    private let shouldFailBatch: Bool

    private(set) var singleCallCount = 0
    private(set) var batchCallCount = 0
    private(set) var lastBatchPathCount = 0

    init(shouldFailBatch: Bool = false) {
        self.shouldFailBatch = shouldFailBatch
    }

    func resolve(storagePath: String) async throws -> URL {
        singleCallCount += 1
        guard let url = Self.stubbedURL(for: storagePath) else {
            throw AstraError.server("Couldn't load that photo.")
        }
        return url
    }

    func resolve(storagePaths: [String]) async throws -> [String: URL] {
        batchCallCount += 1
        lastBatchPathCount = storagePaths.count
        if shouldFailBatch {
            throw AstraError.network("Couldn't load your closet photos.")
        }
        return storagePaths.reduce(into: [:]) { result, path in
            result[path] = Self.stubbedURL(for: path)
        }
    }

    /// `.invalid` per RFC 2606 — a URL that is well-formed and guaranteed
    /// never to resolve, so nothing here can accidentally hit the network.
    private static func stubbedURL(for storagePath: String) -> URL? {
        guard let encoded = storagePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://images.astrastyle.invalid/\(encoded)")
    }
}

private struct StubNetworkMonitor: NetworkReachabilityMonitoring {
    let offline: Bool

    func isOffline() async -> Bool { offline }
}

/// A failure that is not an `AstraError`, to prove the catch-all branch
/// maps rather than swallows.
private struct StubUnexpectedError: Error, LocalizedError {
    var errorDescription: String? { "Something outside the typed error surface went wrong." }
}
