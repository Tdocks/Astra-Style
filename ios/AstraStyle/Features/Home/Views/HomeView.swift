//
//  HomeView.swift
//  AstraStyle
//
//  Kyra's Daily Brief (spec §6.11) — the reference implementation other
//  feature modules are patterned after. No network calls happen in this
//  file; everything routes through `HomeViewModel`. Every state spec §21
//  requires is represented: loading (skeleton), loaded, empty, offline
//  (as a banner layered over loaded/empty), and recoverable error (with
//  retry).
//

import SwiftUI

private struct HomeSnapshotDateKey: EnvironmentKey {
    static var defaultValue: Date { .now }
}

extension EnvironmentValues {
    var homeSnapshotDate: Date {
        get { self[HomeSnapshotDateKey.self] }
        set { self[HomeSnapshotDateKey.self] = newValue }
    }
}

public struct HomeView: View {
    @State var viewModel: HomeViewModel
    @Environment(AppRouter.self) var router
    @Environment(AppContainer.self) var container
    @Environment(\.homeSnapshotDate) var snapshotDate
    let shoppingRepository: ShoppingRepository
    @State var inspirationViewModel: InspirationViewModel?
    @State var isPastingLink = false
    @State var isConfirmingPublicLook = false
    @State var wearFeedbackViewModel: WearFeedbackViewModel?

    public init(viewModel: HomeViewModel, shoppingRepository: ShoppingRepository) {
        _viewModel = State(wrappedValue: viewModel)
        self.shoppingRepository = shoppingRepository
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                if viewModel.isOffline, viewModel.state.showsOfflineBannerWhenStale {
                    HomeOfflineBanner()
                        .padding(.horizontal, AstraSpacing.pagePadding)
                }

                content
            }
            .padding(.vertical, AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .refreshable {
            await viewModel.refresh()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            AstraPerformanceSignposts.beginHomeRender()
            await viewModel.onAppear()
        }
        // Same signal Closet already watches: a sheet does not tear down
        // this view, so `.task` never re-fires after Scan One. Without
        // this, Home keeps the pre-scan empty count until pull-to-refresh.
        .onChange(of: router.presentedModal?.id) { previous, current in
            guard current == nil, previous != nil else { return }
            Task { await viewModel.reloadAfterExternalChange() }
        }
        .alert(
            Text(actionFailureTitle),
            isPresented: actionErrorPresented,
            presenting: viewModel.actionError
        ) { _ in
            Button(dismissTitle) { viewModel.clearActionError() }
        } message: { error in
            Text(error.message)
        }
        .confirmationDialog(
            LookbookSharingCopy.confirmationTitle,
            isPresented: $isConfirmingPublicLook,
            titleVisibility: .visible
        ) {
            Button(LookbookSharingCopy.confirmTitle) {
                Task { await viewModel.makeWornLookPublic() }
            }
            Button(LookbookSharingCopy.cancelTitle, role: .cancel) {}
        } message: {
            Text(LookbookSharingCopy.confirmationMessage)
        }
        .sheet(item: $inspirationViewModel) { model in
            InspirationView(viewModel: model)
        }
        .sheet(isPresented: $isPastingLink) {
            ProductLinkPasteSheet(shoppingRepository: shoppingRepository) { candidateID in
                router.push(HomeRoute.productDecision(candidateID: candidateID))
            }
        }
        .onChange(of: viewModel.pendingPaywall) { _, context in
            if let context {
                router.presentModal(.paywall(context: context))
                viewModel.clearPendingPaywall()
            }
        }
    }
}

// MARK: - Previews

#Preview("Loaded") {
    NavigationStack {
        HomeView(
            viewModel: HomeViewModel(provider: PreviewHomeBriefProvider()),
            shoppingRepository: MockShoppingRepository()
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    NavigationStack {
        HomeView(
            viewModel: HomeViewModel(provider: PreviewHomeBriefProvider(mode: .empty)),
            shoppingRepository: MockShoppingRepository()
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

#Preview("Error") {
    NavigationStack {
        HomeView(
            viewModel: HomeViewModel(provider: PreviewHomeBriefProvider(mode: .error)),
            shoppingRepository: MockShoppingRepository()
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

/// A synchronous-feeling preview provider — avoids composing four mock
/// repositories just to drive `#Preview`. Production code and real
/// previews both go through `DefaultHomeBriefProvider` +
/// `Core/Mocks/Mock*Repository`; this one exists purely to make the three
/// state previews above trivial to read.
private struct PreviewHomeBriefProvider: HomeBriefProviding {
    enum Mode { case loaded, empty, error }
    var mode: Mode = .loaded

    func loadTodayBrief(regenerate: Bool) async throws -> HomeBriefData {
        switch mode {
        case .loaded:
            return HomeBriefData(
                greetingName: SampleData.profile.greetingName,
                weather: SampleData.weatherSnapshot,
                schedule: SampleData.scheduleSnapshot,
                brief: SampleData.dailyBrief(),
                primaryOutfit: SampleData.heroOutfit,
                primaryOutfitItems: SampleData.heroOutfitItems(),
            )
        case .empty:
            var brief = SampleData.dailyBrief()
            brief.primaryOutfitID = nil
            return HomeBriefData(
                greetingName: SampleData.profile.greetingName,
                weather: nil,
                schedule: nil,
                brief: brief,
                primaryOutfit: nil,
                primaryOutfitItems: [],
            )
        case .error:
            throw AstraError.network("Check your connection and try again.")
        }
    }

    func markPrimaryOutfitWorn(_ data: HomeBriefData) async throws {}

    func weatherAuthorization() -> WeatherLocationAuthorization { .authorized }
    func requestWeatherPermission() async -> Bool { true }
}
