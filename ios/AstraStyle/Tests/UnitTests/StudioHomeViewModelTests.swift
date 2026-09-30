//
//  StudioHomeViewModelTests.swift
//  AstraStyleTests
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Studio tab gallery")
@MainActor
struct StudioHomeViewModelTests {
    @Test("An empty gallery is empty, not a fake generation")
    func emptyGallery() async {
        let model = StudioHomeViewModel(
            studioRepository: MockStudioRepository(),
            imageURLResolver: MockClosetImageURLResolver()
        )
        await model.onAppear()
        guard case .empty = model.state else {
            Issue.record("expected .empty, got \(model.state)")
            return
        }
    }

    @Test("A saved generation appears on the Studio tab")
    func listsGenerations() async {
        let studio = MockStudioRepository()
        let generation = StudioGeneration(
            id: UUID(),
            userID: SampleData.userID,
            referenceImagePath: "preview/ref.jpg",
            status: .complete,
            resultImagePath: "preview/result.jpg"
        )
        await studio.seed(generation)
        let model = StudioHomeViewModel(
            studioRepository: studio,
            imageURLResolver: MockClosetImageURLResolver()
        )
        await model.onAppear()
        guard case .loaded(let items) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(items.map(\.id) == [generation.id])
    }

    @Test("Loads later gallery pages as the user reaches the last few previews")
    func loadsNextPageOnDemand() async {
        let studio = MockStudioRepository()
        let generations = (0..<25).map { index in
            StudioGeneration(
                id: UUID(),
                userID: SampleData.userID,
                referenceImagePath: "preview/ref-\(index).jpg",
                status: .failed,
                errorMessage: "Preview unavailable",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        for generation in generations {
            await studio.seed(generation)
        }

        let model = StudioHomeViewModel(
            studioRepository: studio,
            imageURLResolver: MockClosetImageURLResolver()
        )
        await model.onAppear()

        guard case .loaded(let firstPage) = model.state else {
            Issue.record("expected the first gallery page")
            return
        }
        #expect(firstPage.count == StudioHomeViewModel.pageSize)
        #expect(model.hasMore)

        await model.loadMoreIfNeeded(after: firstPage.last?.id ?? UUID())
        guard case .loaded(let allLoaded) = model.state else {
            Issue.record("expected both gallery pages")
            return
        }
        #expect(allLoaded.count == 25)
        #expect(Set(allLoaded.map(\.id)).count == 25)
        #expect(!model.hasMore)
    }
}
