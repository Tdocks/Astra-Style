//
//  ClosetView.swift
//  AstraStyle
//
//  The Closet tab's root screen (spec §6.14 "Closet overview"): the
//  header — My Closet, add, scan, filter, view mode, search — the eight
//  category tiles, the metrics row, and the whole-closet grid beneath
//  them. No network call happens in this file; everything goes through
//  `ClosetViewModel`.
//
//  Every state spec §21 asks for is here: skeleton, loaded, four
//  distinct empty states, a recoverable error with a retry that only
//  appears when retrying can succeed, and an offline banner layered over
//  content rather than replacing it.
//
//  "ALL ITEMS" HAS NO ROUTE, AND IS NOT GIVEN ONE.
//  `ClosetRoute` (App/AppRouter.swift) has a `.category(_)` case and no
//  `.allItems`, and this ticket does not own that enum. Three ways out
//  were available: reuse an unrelated case, invent one, or put the
//  all-items grid on this screen. The third is the honest one and is what
//  is built here — the eighth tile scrolls to the whole-closet grid that
//  is already on this page. Nothing is faked, no route is invented, and
//  the tile does something real the first time it is tapped.
//
//  It also happens to be where the rest of §6.14 belongs, and that has
//  now been collected. The metrics row sits above this grid and the
//  editorial-grid / compact-list / colour-spectrum toggle changes how it
//  renders. Had "All items" been a pushed screen, both would have had to
//  live somewhere the user reaches only by tapping one of eight tiles.
//
//  THE FILTER BUTTON, AND WHAT IT REPLACED.
//  This header used to carry a paragraph arguing that §6.14's filter
//  control had to stay ABSENT, because the panel behind it did not exist
//  and a control that opens an apology is the dead button spec §22 rules
//  out by name. That reasoning is discharged rather than overturned:
//  `ClosetFilterPanelView` is built and tested, so the door to it is
//  real. The button is here, beside add and scan, and it opens the panel
//  as a sheet over this screen.
//
//  It is drawn CONDITIONALLY, which is the same argument one level down.
//  A closet that can offer no filter values at all — nothing in it, or a
//  handful of pieces differing in nothing — puts a panel behind this
//  button with a sentence and no chips, so the button is not drawn.
//  `ClosetFilterButton`'s own header states the rule and the half of it
//  that is easy to drop: `!options.isEmpty || activeFacetCount > 0`. The
//  second clause is what stops a man who filtered down to two garments
//  from watching the only control that could undo it disappear along
//  with the chips.
//
//  `ClosetRoute.filters` stays unused. The panel is a sheet over this
//  screen, not a pushed destination, because it applies as it is tapped
//  and the closet behind it has to be visible changing — the whole reason
//  there is no Apply step (see `ClosetFilterPanelView`'s header). Pushing
//  it would hide the thing it is editing.
//
//  THE VIEW MODE IS PERSISTED, NOT HELD.
//  `@AppStorage` rather than `@State`, under a key
//  `ClosetCategoryView` reads too. A chosen layout is a preference, and
//  one that resets on every launch is a control that keeps undoing
//  itself; one that resets when the user pushes into a category is two
//  closets that disagree about a choice he made once. `ClosetViewMode`
//  is written for exactly this — its raw values are a persistence
//  contract pinned by tests, so renaming a case cannot silently drop
//  every existing user back to the grid.
//
//  AND THE ADD BUTTON PASSES THAT SAME TEST, WHICH IS WHY IT IS HERE.
//  The rule the filter button was held back by is not "§6.14 lists it" —
//  it is "does the thing behind it exist". `ClosetItemFormView` and
//  `ClosetItemFormViewModel.adding(...)` are built, tested and write real
//  `closet_items` rows, and until this button existed they had no call
//  site anywhere in the app: the tab's only way in was the scan button,
//  and at the time `AppRouter.startScan()` still reached a placeholder.
//  So the Closet tab shipped with no way to put a garment in it at all.
//  That is the same §22 failure the filter button was being kept out to
//  avoid, arrived at from the other direction, and this is the control
//  that fixes it. (The scanner modal is real now — capture + import —
//  but review/cataloguing still lands later.)
//
//  It sits BEFORE the scan button rather than after it so the camera keeps
//  the trailing corner it already has — the two are the same pair of ideas
//  ("type it in" / "photograph it") in reading order, and moving the one
//  that already works would be churn for its own sake. It is deliberately
//  the same icon weight as scan, not a filled primary: manual entry is the
//  path that works today, not the path the spec leads with, and the header
//  should not re-rank itself the moment the scanner lands.
//
//  The same door is repeated in the empty states, which is where it
//  matters most — see `ClosetEmptyStateView`'s header for which of the
//  four carry it and which must not.
//
//  THE HEADER ROW HAD TO BE RESTRUCTURED, AND NOT ONLY FOR LARGE TYPE.
//  It now carries a display-weight title and FOUR glyph controls — add,
//  scan, filter, view mode. That does not fit on one line, and the first
//  place it stops fitting is not an accessibility size: at the default
//  text size on a 320pt-wide phone, four controls at the minimum tap
//  target leave the serif "My Closet" about a hundred points, so the
//  title compresses or truncates before Dynamic Type is touched at all.
//  A branch keyed to `isAccessibilitySize` — the idiom used elsewhere in
//  this feature — would therefore have fixed the loud half of the problem
//  and left the quiet half shipping.
//
//  So the choice is made by MEASUREMENT rather than by a threshold.
//  `ViewThatFits` offers the one-line header first and falls back to the
//  title with the controls on their own row beneath it, which is correct
//  at every combination of screen width and text size rather than at the
//  ones someone thought to guess. The fallback row is an
//  `AstraWrappingHStack`, so at the largest accessibility sizes — where
//  a 24pt glyph scales past 60 — the four controls wrap onto a second
//  line instead of running off the edge. Nothing here truncates, scales
//  text down, or scrolls sideways: those are the three escapes spec §19
//  rules out, and this feature has already argued each of them down once
//  (`ClosetMetricsRow`, `AstraWrappingHStack`).
//

import SwiftUI

public struct ClosetView: View {
    @State private var viewModel: ClosetViewModel
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the manual add form is up. View state, not router state:
    /// `AppModalRoute` is for modals any tab can raise (the scanner, the
    /// paywall), and this one belongs to this screen and closes back onto
    /// it.
    @State private var isAddingItem = false

    /// Whether the filter panel is up. View state for the same reason
    /// `isAddingItem` is: it belongs to this screen and closes back onto
    /// it. The values it edits are NOT view state — they live on the view
    /// model, because the grid, the category tile counts and the empty
    /// state all read them.
    @State private var isFiltering = false

    /// Which of spec §6.14's three layouts the closet is drawn in.
    ///
    /// Persisted, and under a key `ClosetCategoryView` also reads — see
    /// this file's header. The literal key is spelled out in both places
    /// rather than hoisted into a shared constant only because
    /// `@AppStorage` needs it at the property wrapper, and a two-screen
    /// preference with the key visible at both call sites is easier to
    /// keep honest than one indirection away from either.
    @AppStorage("closet.viewMode") private var viewMode: ClosetViewMode = .editorialGrid
    /// Display preference, so it persists per device and never travels with
    /// the account — the same reasoning as `closet.viewMode` beside it. On by
    /// default: the cut-out is what §6.15 describes, and a man who dislikes
    /// one particular result turns it off rather than opting in to the
    /// intended rendering.
    @AppStorage("closet.cutouts") private var showsCutouts = true

    /// Anchor for the "All items" tile. A constant rather than a `UUID()`
    /// so it survives the view being rebuilt mid-scroll.
    private static let allItemsSectionID = "closet.all-items"

    public init(viewModel: ClosetViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                    if viewModel.isOffline, viewModel.state.showsOfflineBannerWhenStale {
                        ClosetOfflineBanner()
                            .padding(.horizontal, AstraSpacing.pagePadding)
                    }

                    header
                    content(scrollProxy: proxy)
                }
                .padding(.vertical, AstraSpacing.pagePadding)
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await viewModel.refresh()
        }
        // The screen states its own title editorially, in the serif
        // display face; a second inline copy in the navigation bar would
        // say "My Closet" twice on one screen.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.onAppear()
        }
        .onAppear { viewModel.prefersCutouts = showsCutouts }
        .onChange(of: showsCutouts) { _, prefers in
            // The view model clears its resolved URLs on this change, so the
            // grid re-signs against whichever image the user just asked for.
            viewModel.prefersCutouts = prefers
        }
        // The scanner and the add-item sheet both create garments this
        // screen is showing, and neither of them can tell it so: a sheet
        // does not remove the view underneath, so `.task` never re-fires.
        // Watching the router's own modal state is the smallest true
        // signal — when a modal that could have written to the closet goes
        // away, re-read the closet.
        .onChange(of: router.presentedModal?.id) { previous, current in
            guard current == nil, previous != nil else { return }
            Task { await viewModel.reloadAfterExternalChange() }
        }
        .onChange(of: isAddingItem) { wasPresented, isPresented in
            guard wasPresented, !isPresented else { return }
            Task { await viewModel.reloadAfterExternalChange() }
        }
        .sheet(isPresented: $isAddingItem) {
            ClosetAddItemSheet(makeViewModel: viewModel.makeAddItemViewModel) {
                isAddingItem = false
            }
        }
        .sheet(isPresented: $isFiltering) {
            ClosetFilterPanelView(
                filters: $viewModel.filters,
                // Both of these are answered against the SEARCH-NARROWED,
                // FILTER-FREE closet, which is the scope
                // `ClosetFilterOptions`'s header asks the presenter for.
                // Chips then describe garments the screen is actually
                // showing, and neither the chips nor the count can move
                // under the user's finger as he taps — the only control
                // that could move them is the search field, and it is
                // behind this sheet.
                options: viewModel.filterOptions,
                matchCount: { $0.apply(to: viewModel.searchNarrowedItems).count },
                onDone: { isFiltering = false }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            // See this file's header for why this is measured rather than
            // branched on a text-size threshold.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: AstraSpacing.sm) {
                    title

                    Spacer(minLength: AstraSpacing.sm)

                    // A plain `HStack` in THIS candidate on purpose. An
                    // `AstraWrappingHStack` here would wrap silently to
                    // fit whatever width it was offered, report that it
                    // fits, and this candidate would always win — so the
                    // header would quietly grow a second line of controls
                    // beside a squeezed title instead of falling back to
                    // the layout below.
                    HStack(spacing: AstraSpacing.sm) { headerControls }
                }

                VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                    title
                    AstraWrappingHStack(spacing: AstraSpacing.sm) { headerControls }
                }
            }

            if viewModel.state.hasSearchableContent {
                AstraTextField(
                    String(localized: "Search", comment: "Closet search field label"),
                    text: $viewModel.searchText,
                    placeholder: String(localized: "Name, brand, or colour", comment: "Closet search field placeholder"),
                    submitLabel: .search,
                    autocapitalization: .never
                )
            }
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
    }

    private var title: some View {
        Text(String(localized: "My Closet", comment: "Closet tab title"))
            .astraText(.displayL)
            .foregroundStyle(AstraColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The header controls, in one place so both `ViewThatFits`
    /// candidates draw the same set in the same order rather than two
    /// lists that can drift apart.
    ///
    /// Order is reading order, and it is the order the two original
    /// controls already had: the two ways to PUT something in the closet
    /// first (type it in, photograph it), then the two that change what
    /// you see of what is already in it (narrow it, re-lay it out). The
    /// last two are conditional — each is drawn only where it can change
    /// something, so the row is between two and four controls wide and
    /// the layout below has to survive all three cases.
    @ViewBuilder
    private var headerControls: some View {
        addButton
        scanButton
        filterButton
        // Only where there is a grid for it to re-lay out. A layout
        // toggle above a skeleton, an error, or the empty-closet state is
        // a control that changes nothing visible — the same test the
        // search field beside it already passes, and the same one §22
        // applies to every other control on this screen.
        if isShowingWholeClosetGrid {
            ClosetViewModeToggle(selection: $viewMode, showsCutouts: $showsCutouts)
        }
    }

    /// Whether the whole-closet grid is on screen right now.
    ///
    /// Mirrors the branch in `allItemsSection` rather than re-deriving
    /// it: `hasSearchableContent` is the loaded-and-non-empty test (and
    /// is what rules out the skeleton and the error state, which
    /// `emptyReason(for:)` deliberately answers `nil` for), and
    /// `emptyReason(for: nil) == nil` is the "and something survived the
    /// narrowing" half.
    private var isShowingWholeClosetGrid: Bool {
        viewModel.state.hasSearchableContent && viewModel.emptyReason(for: nil) == nil
    }

    /// §6.14's filter control, drawn only where it can do something.
    ///
    /// The condition is `ClosetFilterButton`'s own documented rule. The
    /// second clause is the one that matters: filtering down to two
    /// garments can itself empty the option list, and without it the
    /// control that undoes the filter would vanish at exactly the moment
    /// the user needs it.
    @ViewBuilder
    private var filterButton: some View {
        // Derived once per pass and reused, rather than read twice: this
        // is a walk over the closet per read, and the sheet below reads
        // it again when it opens.
        let options = viewModel.filterOptions
        let activeFacetCount = viewModel.filters.activeFacetCount

        if !options.isEmpty || activeFacetCount > 0 {
            ClosetFilterButton(activeFacetCount: activeFacetCount) {
                isFiltering = true
            }
        }
    }

    /// Opens the manual garment form.
    ///
    /// This sits in the header and not only in the empty state, because
    /// the empty state disappears the moment the closet holds one item —
    /// so an empty-state-only door lets a man add his first garment and
    /// then never a second. It is also, until `P3-SCAN-01` ships, the only
    /// working way into the closet at all: the button beside it reaches a
    /// scanner flow that does not exist yet.
    ///
    /// Drawn as a secondary weight to the scan button rather than as its
    /// equal. Scanning is the intended path once it exists, and the header
    /// should not be re-taught later.
    private var addButton: some View {
        Button {
            isAddingItem = true
        } label: {
            Image(systemName: "plus")
                .astraIcon(.emphasis)
                // An icon is a fill, not text (spec §3 / docs/07).
                .foregroundStyle(AstraColor.accentChampagne)
                .frame(minWidth: AstraSize.minTapTarget, minHeight: AstraSize.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "Add an item", comment: "VoiceOver label for the closet manual add button")))
        .accessibilityHint(Text(String(localized: "Types in a piece without using the camera", comment: "VoiceOver hint for the closet manual add button")))
        .accessibilityIdentifier("closet.header.addManually")
    }

    /// Opens the scanner flow (spec §4 presents capture modally, and
    /// `AppRouter.startScan()` is the one entry point for it).
    ///
    /// A `Menu` rather than a plain button, because batch is a peer of
    /// single-item capture and not a setting on it. It costs the common case
    /// one tap, which is the honest price of having two modes at all — the
    /// alternative considered was hiding batch behind a long press, and an
    /// affordance nobody can find is the same as the placeholder this
    /// replaced.
    private var scanButton: some View {
        Menu {
            Button(String(localized: "Scan One Piece", comment: "Closet scan menu: single item"),
                   systemImage: "camera.viewfinder") {
                router.startScan()
            }
            Button(String(localized: "Add Several at Once", comment: "Closet scan menu: batch"),
                   systemImage: "square.stack.3d.up") {
                router.startScan(mode: .batchCloset)
            }
        } label: {
            Image(systemName: "camera.viewfinder")
                .astraIcon(.emphasis)
                // An icon is a fill, not text, so this is the plain
                // champagne token (spec §3 / docs/07).
                .foregroundStyle(AstraColor.accentChampagne)
                .frame(minWidth: AstraSize.minTapTarget, minHeight: AstraSize.minTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(String(localized: "Scan an item", comment: "VoiceOver label for the closet scan button")))
        .accessibilityHint(Text(String(localized: "Adds a piece to your closet with the camera, one at a time or several together", comment: "VoiceOver hint for the closet scan button")))
        .accessibilityIdentifier("closet.header.scan")
    }

    // MARK: - Content

    @ViewBuilder
    private func content(scrollProxy: ScrollViewProxy) -> some View {
        switch viewModel.state {
        case .loading:
            ClosetLoadingSkeletonView(columnCount: ClosetGridMetrics.columnCount(for: dynamicTypeSize))

        case .failed(let error):
            ClosetErrorStateView(error: error) {
                Task { await viewModel.retry() }
            }

        case .empty, .loaded:
            loadedContent(scrollProxy: scrollProxy)
        }
    }

    @ViewBuilder
    private func loadedContent(scrollProxy: ScrollViewProxy) -> some View {
        // A closet with nothing in it gets the empty state and nothing
        // else: eight tiles all reading zero above it would be eight
        // controls that lead to eight more empty screens.
        if viewModel.emptyReason(for: nil) == .closetIsEmpty {
            emptyState(.closetIsEmpty)
        } else {
            categoryTiles(scrollProxy: scrollProxy)
            metricsRow
            allItemsSection
        }
    }

    /// §6.14's metrics, between the category tiles and the grid — which is
    /// where `ClosetMetricsRow`'s own header places it, and it is the one
    /// spot on this page where a summary of the whole closet reads as
    /// context for what is below rather than as a headline above what is
    /// above.
    ///
    /// Its figures cover the WHOLE closet, not the narrowed view; the
    /// reasoning is on `ClosetViewModel.metrics`. Most worn and least
    /// worn are the only tiles that name a garment, so they are the only
    /// ones that lead anywhere, and they push the same item-detail route
    /// a grid tile does — reached by id, so a garment the current search
    /// excludes is still reachable from the figure that named it.
    private var metricsRow: some View {
        ClosetMetricsRow(metrics: viewModel.metrics) { itemID in
            router.push(ClosetRoute.itemDetail(itemID: itemID))
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
    }

    private func categoryTiles(scrollProxy: ScrollViewProxy) -> some View {
        LazyVGrid(columns: ClosetGridMetrics.columns(for: dynamicTypeSize), spacing: AstraSpacing.md) {
            ForEach(ClothingCategory.allCases, id: \.self) { category in
                ClosetCategoryTile(
                    title: category.displayName,
                    count: viewModel.count(in: category),
                    accessibilityIdentifier: "closet.category.\(category.rawValue)"
                ) {
                    router.push(ClosetRoute.category(category))
                }
            }

            ClosetCategoryTile(
                title: String(localized: "All items", comment: "Closet category tile covering the whole wardrobe"),
                count: viewModel.visibleItemCount,
                accessibilityIdentifier: "closet.category.all"
            ) {
                withAnimation(AstraMotion.aware(AstraMotion.standard, reduceMotion: reduceMotion)) {
                    scrollProxy.scrollTo(Self.allItemsSectionID, anchor: .top)
                }
            }
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
    }

    @ViewBuilder
    private var allItemsSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(title: String(localized: "All items", comment: "Header above the whole-closet grid"))
                .padding(.horizontal, AstraSpacing.pagePadding)
                .id(Self.allItemsSectionID)

            if let reason = viewModel.emptyReason(for: nil) {
                emptyState(reason)
            } else {
                allItemsGrid
                    .padding(.horizontal, AstraSpacing.pagePadding)
            }
        }
    }

    /// The whole-closet section, drawn in whichever of spec §6.14's three
    /// layouts is selected.
    ///
    /// All three take the same four arguments in the same order, which is
    /// the property `ClosetViewMode`'s header calls the point of the type
    /// — so this switch chooses a renderer and nothing else. In
    /// particular none of them filters or sorts what it is handed:
    /// `ClosetColorSpectrum` re-orders internally, so it gets the closet
    /// in normal order like the other two, and the image-resolution
    /// callback is identical in all three so scrolling any of them feeds
    /// the same coalescing pass.
    @ViewBuilder
    private var allItemsGrid: some View {
        switch viewMode {
        case .editorialGrid:
            ClosetItemGrid(
                items: viewModel.visibleItems,
                imageURL: { viewModel.imageURL(for: $0) },
                onTileVisible: { viewModel.imageNeeded(for: $0) },
                onTileTap: { router.push(ClosetRoute.itemDetail(itemID: $0.id)) }
            )

        case .compactList:
            ClosetCompactList(
                items: viewModel.visibleItems,
                imageURL: { viewModel.imageURL(for: $0) },
                onRowVisible: { viewModel.imageNeeded(for: $0) },
                onRowTap: { router.push(ClosetRoute.itemDetail(itemID: $0.id)) }
            )

        case .colorSpectrum:
            ClosetColorSpectrum(
                items: viewModel.visibleItems,
                imageURL: { viewModel.imageURL(for: $0) },
                onTileVisible: { viewModel.imageNeeded(for: $0) },
                onTileTap: { router.push(ClosetRoute.itemDetail(itemID: $0.id)) }
            )
        }
    }

    private func emptyState(_ reason: ClosetViewModel.EmptyReason) -> some View {
        ClosetEmptyStateView(
            reason: reason,
            onScan: { router.startScan() },
            onScanSeveral: { router.startScan(mode: .batchCloset) },
            onAddManually: { isAddingItem = true },
            onClearSearch: { viewModel.clearSearch() },
            onClearFilters: { viewModel.clearFilters() }
        )
    }
}

// MARK: - Shared grid

/// The editorial grid itself, shared by the whole-closet section above and
/// by `ClosetCategoryView`. Extracted so the two screens cannot drift into
/// two different grids — the column rule, spacing and tile are stated once.
struct ClosetItemGrid: View {
    let items: [ClosetItem]
    let imageURL: (ClosetItem) -> URL?
    let onTileVisible: (ClosetItem) -> Void
    let onTileTap: (ClosetItem) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(columns: ClosetGridMetrics.columns(for: dynamicTypeSize), spacing: AstraSpacing.lg) {
            ForEach(items) { item in
                ClosetGridTile(
                    item: item,
                    imageURL: imageURL(item),
                    onVisible: { onTileVisible(item) },
                    onTap: { onTileTap(item) }
                )
            }
        }
    }
}

// MARK: - Previews

#Preview("Loaded") {
    NavigationStack {
        ClosetView(
            viewModel: ClosetViewModel(
                closetRepository: MockClosetRepository(),
                imageURLResolver: MockClosetImageURLResolver()
            )
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

#Preview("Empty closet") {
    NavigationStack {
        ClosetView(
            viewModel: ClosetViewModel(
                closetRepository: MockClosetRepository(items: []),
                imageURLResolver: MockClosetImageURLResolver()
            )
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
