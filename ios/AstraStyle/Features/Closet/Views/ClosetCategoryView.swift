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

import SwiftUI

public struct ClosetCategoryView: View {
    private let category: ClothingCategory

    @State private var viewModel: ClosetViewModel
    @State private var isAddingItem = false
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        .task {
            await viewModel.onAppear()
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
                    onAddManually: { isAddingItem = true },
                    onClearSearch: { viewModel.clearSearch() }
                )
            } else {
                ClosetItemGrid(
                    items: viewModel.items(in: category),
                    imageURL: { viewModel.imageURL(for: $0) },
                    onTileVisible: { viewModel.imageNeeded(for: $0) },
                    onTileTap: { router.push(ClosetRoute.itemDetail(itemID: $0.id)) }
                )
                .padding(.horizontal, AstraSpacing.pagePadding)
            }
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
