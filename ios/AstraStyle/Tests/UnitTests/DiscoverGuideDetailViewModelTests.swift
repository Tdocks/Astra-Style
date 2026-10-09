import Testing
@testable import AstraStyle

@Suite("Discover guide detail")
@MainActor
struct DiscoverGuideDetailViewModelTests {
    @Test("A configured guide opens as a readable article")
    func loadsGuideBySlug() async {
        let guide = draftGuide(id: "fit-shoulder")
        let model = DiscoverGuideDetailViewModel(
            slug: guide.id,
            repository: StaticDiscoverEditorialRepository(guides: [guide])
        )

        await model.load()

        guard case .loaded(let loaded) = model.state else {
            Issue.record("expected an article state")
            return
        }
        #expect(loaded.id == "fit-shoulder")
        #expect(loaded.sections.count == 1)
    }

    @Test("Removed or unpublished guide routes show unavailable")
    func missingGuideIsUnavailable() async {
        let model = DiscoverGuideDetailViewModel(
            slug: "removed-guide",
            repository: StaticDiscoverEditorialRepository(guides: [])
        )

        await model.load()

        guard case .unavailable = model.state else {
            Issue.record("removed editorial should not become an empty page")
            return
        }
    }

    @Test("Repository failure stays retryable instead of displaying stale text")
    func repositoryFailureIsExplicit() async {
        let model = DiscoverGuideDetailViewModel(
            slug: "fit-shoulder",
            repository: StaticDiscoverEditorialRepository(guides: [], shouldFail: true)
        )

        await model.load()

        guard case .failed = model.state else {
            Issue.record("repository failure should have a visible retry state")
            return
        }
    }
}

private func draftGuide(id: String) -> DiscoverGuide {
    DiscoverGuide(
        id: id,
        sortOrder: 1,
        kind: .fitGuide,
        title: "Read the shoulder first",
        summary: "A quick garment fit check.",
        readingMinutes: 3,
        season: nil,
        sections: [DiscoverGuideSection(heading: "Move", body: "Reach forward and sit.")],
        isPublished: true,
        editorialLabel: nil,
        isSponsored: nil,
        sponsorshipDisclosure: nil,
        sources: nil,
        reviewedAt: nil
    )
}
