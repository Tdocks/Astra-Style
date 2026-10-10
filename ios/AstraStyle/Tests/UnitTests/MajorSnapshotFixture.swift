import SwiftUI
@testable import AstraStyle

enum MajorSnapshotScreen: String, CaseIterable {
    case home
    case closet
    case outfitDetail = "outfit-detail"
    case kyraConversation = "kyra-conversation"
    case studioGallery = "studio-gallery"
    case studioDetail = "studio-detail"
    case paywall
    case profile
}

enum MajorSnapshotState: String {
    case populated
    case empty
}

@MainActor
enum MajorSnapshotFixture {
    static func make(screen: MajorSnapshotScreen, state: MajorSnapshotState) async throws -> AnyView {
        let router = AppRouter()
        let container = AppContainer.preview()
        let content: AnyView

        switch screen {
        case .home:
            let viewModel = HomeViewModel(
                provider: SnapshotHomeBriefProvider(isEmpty: state == .empty),
                networkMonitor: StaticNetworkReachabilityMonitor()
            )
            await viewModel.onAppear()
            content = AnyView(HomeView(viewModel: viewModel, shoppingRepository: container.shoppingRepository))
        case .closet:
            content = AnyView(try await closetView(isEmpty: state == .empty))
        case .outfitDetail:
            content = AnyView(try await outfitDetail(isUnavailable: state == .empty))
        case .kyraConversation:
            content = AnyView(try await kyraConversation(isEmpty: state == .empty))
        case .studioGallery:
            content = AnyView(try await studioGallery(isEmpty: state == .empty))
        case .studioDetail:
            content = AnyView(try await studio(isFailed: state == .empty))
        case .paywall:
            content = AnyView(try await paywall(hasOfferings: state == .populated))
        case .profile:
            await seedProfile(container, isEmpty: state == .empty)
            content = AnyView(ProfileView())
        }

        return AnyView(
            NavigationStack { content }
                .environment(router)
                .environment(container)
                .environment(container.settings)
                .environment(\.homeSnapshotDate, SnapshotClock.date)
        )
    }

    private static func closetView(isEmpty: Bool) async throws -> ClosetView {
        let closet = MockClosetRepository(items: isEmpty ? [] : SampleData.closetItems)
        let outfits = MockOutfitRepository()
        let profile = MockProfileRepository()
        let resolver = NoRemoteSnapshotImageResolver()
        let network = StaticNetworkReachabilityMonitor()
        let viewModel = ClosetViewModel(
            closetRepository: closet,
            imageURLResolver: resolver,
            currentUserID: { SampleData.userID },
            networkMonitor: network
        )
        let looksViewModel = ClosetLooksViewModel(
            outfitRepository: outfits,
            closetRepository: closet,
            profileRepository: profile,
            imageURLResolver: resolver
        )
        await viewModel.onAppear()
        await looksViewModel.onAppear()
        return ClosetView(viewModel: viewModel, looksViewModel: looksViewModel)
    }

    private static func outfitDetail(isUnavailable: Bool) async throws -> OutfitDetailView {
        let id = isUnavailable ? fixedID("00000000-0000-4000-8000-000000000bad") : SampleData.heroOutfit.id
        let viewModel = OutfitDetailViewModel(
            outfitID: id,
            outfitRepository: MockOutfitRepository(),
            closetRepository: MockClosetRepository(),
            closetImageURLResolver: NoRemoteSnapshotImageResolver(),
            profileRepository: MockProfileRepository(),
            networkMonitor: StaticNetworkReachabilityMonitor()
        )
        await viewModel.onAppear()
        return OutfitDetailView(viewModel: viewModel)
    }

    private static func kyraConversation(isEmpty: Bool) async throws -> KyraConversationView {
        let repository = MockKyraRepository()
        let viewModel = KyraConversationViewModel(
            threadID: nil,
            kyraRepository: repository,
            outfitRepository: MockOutfitRepository(),
            closetRepository: MockClosetRepository(),
            shoppingRepository: MockShoppingRepository(),
            imageURLResolver: NoRemoteSnapshotImageResolver(),
            networkMonitor: StaticNetworkReachabilityMonitor(),
            analyticsClient: NoOpAnalyticsClient()
        )
        await viewModel.onAppear()
        if !isEmpty { await viewModel.send(prompt: "What should I wear to a client meeting?") }
        return KyraConversationView(viewModel: viewModel)
    }

    private static func studio(isFailed: Bool) async throws -> StudioGenerationDetailView {
        let id = fixedID("00000000-0000-4000-8000-000000000007")
        let repository = MockStudioRepository()
        await repository.seed(StudioGeneration(
            id: id,
            userID: SampleData.userID,
            referenceImagePath: "",
            status: isFailed ? .failed : .complete,
            errorMessage: isFailed ? "This estimate could not be prepared. Try again." : nil,
            createdAt: SnapshotClock.date,
            updatedAt: SnapshotClock.date
        ))
        let viewModel = StudioGenerationDetailViewModel(
            generationID: id,
            studioRepository: repository,
            imageURLResolver: NoRemoteSnapshotImageResolver(),
            exporter: MockStudioEstimateExporter()
        )
        await viewModel.onAppear()
        return StudioGenerationDetailView(viewModel: viewModel)
    }

    private static func studioGallery(isEmpty: Bool) async throws -> StudioHomeView {
        let repository = MockStudioRepository()
        if !isEmpty {
            await repository.seed(StudioGeneration(
                id: fixedID("00000000-0000-4000-8000-000000000017"),
                userID: SampleData.userID,
                referenceImagePath: "",
                status: .complete,
                createdAt: SnapshotClock.date,
                updatedAt: SnapshotClock.date
            ))
        }
        let viewModel = StudioHomeViewModel(
            studioRepository: repository,
            imageURLResolver: NoRemoteSnapshotImageResolver()
        )
        await viewModel.onAppear()
        return StudioHomeView(viewModel: viewModel)
    }

    private static func paywall(hasOfferings: Bool) async throws -> PaywallView {
        let offerings: [PaywallOffering] = hasOfferings ? [
            PaywallOffering(id: .monthly, displayName: "Premium Monthly", displayPrice: "$12.99"),
            PaywallOffering(id: .annual, displayName: "Premium Annual", displayPrice: "$79.99")
        ] : []
        let purchasing = MockStoreKitPurchasing(offerings: offerings)
        let viewModel = PaywallViewModel(
            context: .outfitGenerationLimit,
            purchasing: purchasing,
            subscriptionRepository: MockSubscriptionRepository()
        )
        await viewModel.onAppear()
        return PaywallView(viewModel: viewModel)
    }

    private static func seedProfile(_ container: AppContainer, isEmpty: Bool) async {
        guard !isEmpty,
              let shopping = container.shoppingRepository as? MockShoppingRepository,
              let candidates = try? await shopping.fetchCuratedProducts(category: nil),
              candidates.count > 1 else { return }
        try? await shopping.addToWishlist(candidateID: candidates[0].id)
        await shopping.seedPurchase(candidateID: candidates[1].id, purchasedAt: SnapshotClock.date)
    }

}

private struct SnapshotHomeBriefProvider: HomeBriefProviding {
    let isEmpty: Bool

    func loadTodayBrief(regenerate: Bool) async throws -> HomeBriefData {
        let items = SampleData.heroOutfitItems()
        var outfit = SampleData.heroOutfit
        outfit.createdAt = SnapshotClock.date
        outfit.updatedAt = SnapshotClock.date
        let brief = DailyBrief(
            id: fixedID("00000000-0000-4000-8000-000000000011"),
            userID: SampleData.userID,
            briefDate: SnapshotClock.date,
            primaryOutfitID: isEmpty ? nil : outfit.id,
            weatherSnapshot: SampleData.weatherSnapshot,
            kyraMessage: isEmpty ? nil : "A simple, polished layer for today."
        )
        let garments = items.compactMap { outfitItem -> LookGarment? in
            guard let id = outfitItem.closetItemID,
                  let garment = SampleData.closetItems.first(where: { $0.id == id }) else { return nil }
            return LookGarment(item: garment, role: outfitItem.role)
        }
        let counts = Dictionary(grouping: SampleData.closetItems, by: \.category).mapValues(\.count)
        return HomeBriefData(
            greetingName: SampleData.profile.greetingName,
            weather: SampleData.weatherSnapshot,
            schedule: SampleData.scheduleSnapshot,
            brief: brief,
            primaryOutfit: isEmpty ? nil : outfit,
            primaryOutfitItems: isEmpty ? [] : items,
            closetRoleCounts: isEmpty ? [:] : counts,
            wearableRoleCounts: isEmpty ? [:] : counts,
            lookGarments: isEmpty ? [] : garments
        )
    }

    func markPrimaryOutfitWorn(_ data: HomeBriefData) async throws {}
    func weatherAuthorization() -> WeatherLocationAuthorization { .authorized }
    func requestWeatherPermission() async -> Bool { true }
}

enum SnapshotClock {
    static let date = Date(timeIntervalSince1970: 1_791_000_000)
    static let timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
}

private struct NoRemoteSnapshotImageResolver: ClosetImageURLResolving {
    func resolve(storagePath: String) async throws -> URL {
        throw AstraError.unimplemented("Snapshot fixtures do not load remote images.")
    }

    func resolve(storagePaths: [String]) async throws -> [String: URL] { [:] }
}

private func fixedID(_ hex: String) -> UUID {
    UUID(uuidString: hex) ?? SampleData.userID
}
