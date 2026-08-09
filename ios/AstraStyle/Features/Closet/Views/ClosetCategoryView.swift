//
//  ClosetCategoryView.swift
//  AstraStyle
//
//  The screen a category tile pushes to: the editorial grid narrowed to
//  one `ClothingCategory` — spec §6.14, and the acceptance criterion
//  "tapping a category tile navigates to a filtered view of just that
//  category" in as literal a form as it can be read.
//
//  ITS OWN VIEW MODEL, NOT THE OVERVIEW'S.
//  `ClosetDestinationView` builds the screens `ClosetRoute` resolves to
//  from `AppContainer`, so this one arrives with its own `ClosetViewModel`
//  rather than a reference to the overview's. That costs a second
//  `fetchItems()` on push. It is the right trade anyway: a pushed screen
//  that borrows a parent's view model keeps the parent alive for as long
//  as the stack does, and it makes the destination depend on which screen
//  it happened to be pushed from — this one is reachable from a tile
//  today and could be reached from Kyra, from a search result, or from a
//  deep link tomorrow, and it should behave identically in all four cases.
//  Caching reads is the repository's job, not the router's.
//
//  SEARCH IS SHOWN HERE TOO. One rule, stated once: the search field
//  narrows whatever grid it sits above. Applying it invisibly — a stale
//  query silently hiding half a category — is the version that confuses,
//  so the field the query lives in is on screen wherever the query has an
//  effect.
//
//  THE VIEW MODE IS SHOWN HERE TOO, AND READS THE SAME KEY.
//  `@AppStorage("closet.viewMode")` — the same string `ClosetView` uses,
//  so the two closet screens agree about a choice the user made once. A
//  man who switches the closet to a compact list and then taps Knitwear
//  should not be handed a grid; that is the same control undoing itself
//  that persistence exists to prevent, one screen over. Both screens draw
//  the toggle rather than only the root, because a preference the user
//  cannot change from the screen he is looking at is a preference he has
//  to go somewhere else to fix.
//
//  THE FILTER BUTTON IS NOT SHOWN HERE, AND THAT IS THE DECISION, NOT AN
//  OMISSION. Three things say so, and they agree.
//
//  This screen IS spec §6.14's category facet, already applied. Handing
//  it a panel that opens on the other seven would present a control the
//  user has learned holds eight — `ClosetFilterOptions.derive` would drop
//  Category automatically here, since one value covering the whole scope
//  narrows nothing — so the panel would silently differ between two
//  screens for a reason nothing on either explains.
//
//  Worse, it would be a DIFFERENT filter set. This screen holds its own
//  `ClosetViewModel` (see above), so a filter applied here is not the one
//  applied on the root: narrow to navy on the Closet tab, push into Tops,
//  and the panel opens empty; narrow to navy again, pop back, and there
//  are two independent navy filters behind one glyph. That is one control
//  meaning two things, and the fix is a shared filter store, which is a
//  different ticket with a real design question in it (does popping back
//  keep the category's filters?) rather than a line of wiring.
//
//  It would not even be the first narrowing to behave that way: the
//  search query does not carry across the push either, for exactly the
//  same structural reason. But search is a single visible field holding
//  its own state in plain sight, and a man can see at a glance that it is
//  empty. A filter set is a count on a glyph, and an empty one looks
//  identical to no filters at all — so the same structure that is merely
//  surprising for search is genuinely misleading for filters. Search is
//  on screen here and does the narrowing that can be done honestly, which
//  is exactly the position the filter button itself was in before its
//  panel existed.
//
//  THE METRICS ROW IS NOT SHOWN HERE EITHER, and that reasoning holds on
//  inspection rather than by assertion. Four of its five figures are
//  whole-closet statements — total items, estimated closet value, average
//  cost per wear, most and least worn — and `ClosetMetrics.compute(for:)`
//  takes whatever array it is handed, so scoping it to one category would
//  produce five correct numbers under five labels that all claim to be
//  about the closet. Relabelling them per category is a copy change this
//  screen does not own, and "estimated value of your knitwear" is not a
//  figure spec §6.14 asks for.
//

import SwiftUI

public struct ClosetCategoryView: View {
    private let category: ClothingCategory

    @State private var viewModel: ClosetViewModel
    @State private var isAddingItem = false
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The same key `ClosetView` writes — see this file's header.
    @AppStorage("closet.viewMode") private var viewMode: ClosetViewMode = .editorialGrid
    /// The same key `ClosetView` writes, for the same reason the view-mode
    /// key is shared: a display preference the user set on one closet screen
    /// and finds reverted on the other reads as the setting not working.
    @AppStorage("closet.cutouts") private var showsCutouts = true

    public init(category: ClothingCategory, viewModel: ClosetViewModel) {
        self.category = category
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                if viewModel.isOffline, viewModel.state.showsOfflineBannerWhenStale {
                    ClosetOfflineBanner()
                        .padding(.horizontal, AstraSpacing.pagePadding)
                }

                if viewModel.state.hasSearchableContent {
                    AstraTextField(
                        String(localized: "Search", comment: "Closet search field label"),
                        text: $viewModel.searchText,
                        placeholder: String(localized: "Name, brand, or colour", comment: "Closet search field placeholder"),
                        submitLabel: .search,
                        autocapitalization: .never
                    )
                    .padding(.horizontal, AstraSpacing.pagePadding)
                }

                content
            }
            .padding(.vertical, AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await viewModel.refresh()
        }
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        // IN THE NAVIGATION BAR, NOT IN THE PAGE. This screen has no
        // editorial title row to hang a control off — the title is the
        // navigation bar's — and the only other row is the search field,
        // which would have to give up width to a glyph at exactly the
        // text sizes it can least afford to. The bar already reserves a
        // trailing slot, sizes it for Dynamic Type itself, and is where
        // iOS puts view options on a pushed screen.
        //
        // Drawn only when the grid it re-lays out is on screen, for the
        // same reason it is conditional on the Closet root: a layout
        // toggle over a skeleton, an error or an empty category changes
        // nothing the user can see (spec §22).
        .toolbar {
            if isShowingGrid {
                ToolbarItem(placement: .topBarTrailing) {
                    ClosetViewModeToggle(selection: $viewMode, showsCutouts: $showsCutouts)
                }
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .onAppear { viewModel.prefersCutouts = showsCutouts }
        .onChange(of: showsCutouts) { _, prefers in
            viewModel.prefersCutouts = prefers
        }
        // The same sheet the Closet root presents, from the same factory.
        // An empty category offers "Add One by Hand", and a button that
        // opened nothing here would be the dead button spec §22 rules out
        // — so this screen presents the form itself rather than sending
        // the man back a level to find the door.
        .sheet(isPresented: $isAddingItem) {
            ClosetAddItemSheet(makeViewModel: viewModel.makeAddItemViewModel) {
                isAddingItem = false
            }
        }
    }

    /// Whether the category grid is on screen right now — the condition
    /// the view-mode toggle is drawn under. Mirrors the branch in
    /// `content` below: the skeleton and the error state are ruled out by
    /// `hasSearchableContent` (which `emptyReason(for:)` cannot do, since
    /// it deliberately answers `nil` in both), and the empty states by
    /// `emptyReason(for:)` itself.
    private var isShowingGrid: Bool {
        viewModel.state.hasSearchableContent && viewModel.emptyReason(for: category) == nil
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ClosetLoadingSkeletonView(columnCount: ClosetGridMetrics.columnCount(for: dynamicTypeSize))

        case .failed(let error):
            ClosetErrorStateView(error: error) {
                Task { await viewModel.retry() }
            }

        case .empty, .loaded:
            if let reason = viewModel.emptyReason(for: category) {
                ClosetEmptyStateView(
                    reason: reason,
                    onScan: { router.startScan() },
                    onScanSeveral: { router.startScan(mode: .batchCloset) },
                    onAddManually: { isAddingItem = true },
                    onClearSearch: { viewModel.clearSearch() },
                    // Unreachable today and deliberately still wired: no
                    // filter control is presented on this screen (see
                    // this file's header), so `ClosetViewModel.filters`
                    // here is always empty and `.noFilterMatches` cannot
                    // occur. Passing the real recovery rather than an
                    // empty closure means the day a filter DOES reach
                    // this screen, the empty state already works instead
                    // of shipping a button that does nothing.
                    onClearFilters: { viewModel.clearFilters() }
                )
            } else {
                categoryGrid
                    .padding(.horizontal, AstraSpacing.pagePadding)
            }
        }
    }

    /// The category's garments, in whichever of spec §6.14's three
    /// layouts is selected. The same three-way swap `ClosetView` makes,
    /// over `items(in:)` instead of the whole closet — all three
    /// renderers take the same four arguments in the same order, which is
    /// what makes that a switch rather than three screens.
    @ViewBuilder
    private var categoryGrid: some View {
        switch viewMode {
        case .editorialGrid:
            ClosetItemGrid(
                items: viewModel.items(in: category),
                imageURL: { viewModel.imageURL(for: $0) },
                onTileVisible: { viewModel.imageNeeded(for: $0) },
                onTileTap: { router.push(ClosetRoute.itemDetail(itemID: $0.id)) }
            )

        case .compactList:
            ClosetCompactList(
                items: viewModel.items(in: category),
                imageURL: { viewModel.imageURL(for: $0) },
                onRowVisible: { viewModel.imageNeeded(for: $0) },
                onRowTap: { router.push(ClosetRoute.itemDetail(itemID: $0.id)) }
            )

        case .colorSpectrum:
            ClosetColorSpectrum(
                items: viewModel.items(in: category),
                imageURL: { viewModel.imageURL(for: $0) },
                onTileVisible: { viewModel.imageNeeded(for: $0) },
                onTileTap: { router.push(ClosetRoute.itemDetail(itemID: $0.id)) }
            )
        }
    }
}

// MARK: - Previews

#Preview("Category — Tops") {
    NavigationStack {
        ClosetCategoryView(
            category: .top,
            viewModel: ClosetViewModel(
                closetRepository: MockClosetRepository(),
                imageURLResolver: MockClosetImageURLResolver()
            )
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

#Preview("Category — nothing in it") {
    NavigationStack {
        ClosetCategoryView(
            category: .fragrance,
            viewModel: ClosetViewModel(
                closetRepository: MockClosetRepository(),
                imageURLResolver: MockClosetImageURLResolver()
            )
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
