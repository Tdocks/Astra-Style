import Testing
@testable import AstraStyle

@MainActor
@Suite("Closet overview server-backed versatility metric")
struct ClosetVersatilityMetricTests {
    @Test("Displays the server component value and discloses degraded inputs")
    func displaysTheServerVersatilityComponent() async throws {
        let repository = MockClosetRepository(items: SampleData.closetItems)
        let score = WardrobeScoreSnapshot(
            score: SampleData.wardrobeScore,
            activeItemCount: SampleData.closetItems.count,
            confidence: 0.8,
            degradedComponents: [.versatility]
        )
        await repository.setWardrobeScoreSnapshot(score)
        let viewModel = makeViewModel(repository: repository)

        await viewModel.onAppear()

        #expect(viewModel.versatilityMetric == .score(SampleData.wardrobeScore.versatility, degraded: true))
        #expect(Set(viewModel.state.items.map(\.id)) == Set(SampleData.closetItems.map(\.id)))
    }

    @Test("A failed score read leaves the closet loaded and marks only versatility unavailable")
    func scoreFailureDoesNotFailTheCloset() async throws {
        let repository = MockClosetRepository(items: SampleData.closetItems)
        await repository.setWardrobeScoreError(AstraError.network("Score unavailable."))
        let viewModel = makeViewModel(repository: repository)

        await viewModel.onAppear()

        #expect(viewModel.versatilityMetric == .unavailable)
        #expect(Set(viewModel.state.items.map(\.id)) == Set(SampleData.closetItems.map(\.id)))
    }

    @Test("An empty score response is not shown as zero")
    func emptyScoreHasAnExplicitNoDataState() async throws {
        let repository = MockClosetRepository(items: [])
        await repository.setWardrobeScoreSnapshot(WardrobeScoreSnapshot(score: nil, activeItemCount: 0))
        let viewModel = makeViewModel(repository: repository)

        await viewModel.onAppear()

        #expect(viewModel.versatilityMetric == .noData)
        #expect(viewModel.state.items.isEmpty)
    }

    @Test("Pull to refresh updates the score independently of the local closet metrics")
    func refreshReadsUpdatedServerScore() async throws {
        let repository = MockClosetRepository(items: SampleData.closetItems)
        let initialScore = WardrobeScoreSnapshot(
            score: score(versatility: 31),
            activeItemCount: SampleData.closetItems.count
        )
        await repository.setWardrobeScoreSnapshot(initialScore)
        let viewModel = makeViewModel(repository: repository)
        await viewModel.onAppear()
        let localMetrics = viewModel.metrics

        await repository.setWardrobeScoreSnapshot(
            WardrobeScoreSnapshot(score: score(versatility: 84), activeItemCount: SampleData.closetItems.count)
        )
        await viewModel.refresh()

        #expect(viewModel.versatilityMetric == .score(84, degraded: false))
        #expect(viewModel.metrics == localMetrics)
    }

    private func makeViewModel(repository: MockClosetRepository) -> ClosetViewModel {
        ClosetViewModel(
            closetRepository: repository,
            imageURLResolver: MockClosetImageURLResolver(),
            networkMonitor: OnlineTestMonitor()
        )
    }

    private func score(versatility: Int) -> WardrobeScore {
        WardrobeScore(
            overall: 70,
            versatility: versatility,
            fitConfidence: 72,
            occasionCoverage: 68,
            colorCohesion: 75,
            wearUtilization: 61,
            condition: 81,
            redundancyControl: 69
        )
    }
}

private struct OnlineTestMonitor: NetworkReachabilityMonitoring {
    func isOffline() async -> Bool { false }
}
