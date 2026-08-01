//
//  ClosetView.swift
//  AstraStyle
//
//  The Closet tab's root screen (spec §6.14 "Closet overview"): the
//  header — My Closet, search, scan — the eight category tiles, and the
//  whole-closet editorial grid beneath them. No network call happens in
//  this file; everything goes through `ClosetViewModel`.
//
//  Every state spec §21 asks for is here: skeleton, loaded, three
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
//  It also happens to be where the rest of §6.14 belongs. The metrics row
//  and the editorial-grid / compact-list / colour-spectrum toggle are a
//  later ticket, and both act on exactly this grid: the toggle changes how
//  the section below renders, the metrics row sits above it. Had "All
//  items" been a pushed screen, those would have had to live on a screen
//  the user reaches only by tapping one of eight tiles.
//
//  NO FILTER BUTTON YET, DELIBERATELY.
//  Spec §6.14's header lists one, `ClosetRoute.filters` exists as a
//  destination, and the panel behind it is a separate ticket that has not
//  been built. A filter control that opens an apology is a dead button,
//  which spec §22 rules out by name, so the control is absent rather than
//  present-and-hollow — a visible gap in §6.14 is easier to see and
//  cheaper to fix than a control that has taught the user it does nothing.
//  Search is real today and does the narrowing that can be done honestly.
//  The filter button lands with the panel, not before it.
//
//  AND THE ADD BUTTON PASSES THAT SAME TEST, WHICH IS WHY IT IS HERE.
//  The rule the filter button is held back by is not "§6.14 lists it" — it
//  is "does the thing behind it exist". `ClosetItemFormView` and
//  `ClosetItemFormViewModel.adding(...)` are built, tested and write real
//  `closet_items` rows, and until this button existed they had no call
//  site anywhere in the app: the tab's only way in was the scan button,
//  and `AppRouter.startScan()` reaches a placeholder until the scanner
//  ships. So the Closet tab shipped with no way to put a garment in it at
//  all. That is the same §22 failure the filter button is being kept out
//  to avoid, arrived at from the other direction, and this is the control
//  that fixes it.
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
//  three carry it and which must not.
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
        .sheet(isPresented: $isAddingItem) {
            ClosetAddItemSheet(makeViewModel: viewModel.makeAddItemViewModel) {
                isAddingItem = false
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: AstraSpacing.sm) {
                Text(String(localized: "My Closet", comment: "Closet tab title"))
                    .astraText(.displayL)
                    .foregroundStyle(AstraColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: AstraSpacing.sm)

                addButton
                scanButton
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
    private var scanButton: some View {
        Button {
            router.startScan()
        } label: {
            Image(systemName: "camera.viewfinder")
                .astraIcon(.emphasis)
                // An icon is a fill, not text, so this is the plain
                // champagne token (spec §3 / docs/07).
                .foregroundStyle(AstraColor.accentChampagne)
                .frame(minWidth: AstraSize.minTapTarget, minHeight: AstraSize.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "Scan an item", comment: "VoiceOver label for the closet scan button")))
        .accessibilityHint(Text(String(localized: "Adds a piece to your closet with the camera", comment: "VoiceOver hint for the closet scan button")))
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
            allItemsSection
        }
    }

    private func categoryTiles(scrollProxy: ScrollViewProxy) -> some View {
        LazyVGrid(columns: ClosetGridMetrics.columns(for: dynamicTypeSize), spacing: AstraSpacing.md) {
            ForEach(ClothingCategory.allCases, id: \.self) { category in
                ClosetCategoryTile(
                    title: category.displayName,
                    count: viewModel.count(in: category)
                ) {
                    router.push(ClosetRoute.category(category))
                }
            }

            ClosetCategoryTile(
                title: String(localized: "All items", comment: "Closet category tile covering the whole wardrobe"),
                count: viewModel.visibleItemCount
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
                ClosetItemGrid(
                    items: viewModel.visibleItems,
                    imageURL: { viewModel.imageURL(for: $0) },
                    onTileVisible: { viewModel.imageNeeded(for: $0) },
                    onTileTap: { router.push(ClosetRoute.itemDetail(itemID: $0.id)) }
                )
                .padding(.horizontal, AstraSpacing.pagePadding)
            }
        }
    }

    private func emptyState(_ reason: ClosetViewModel.EmptyReason) -> some View {
        ClosetEmptyStateView(
            reason: reason,
            onScan: { router.startScan() },
            onAddManually: { isAddingItem = true },
            onClearSearch: { viewModel.clearSearch() }
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
