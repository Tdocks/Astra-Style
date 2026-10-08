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
    @Test("Pending file removal remains visible even after the gallery becomes empty")
    func pendingRemovalTracking() async throws {
        let studio = MockStudioRepository()
        let generation = StudioGeneration(id: UUID(), userID: SampleData.userID, referenceImagePath: "", status: .complete, resultImagePath: "result")
        await studio.seed(generation)
        await studio.setPendingImageDeletionCount(1)
        let model = StudioHomeViewModel(studioRepository: studio, imageURLResolver: MockClosetImageURLResolver())
        await model.onAppear()
        await model.deleteGeneration(id: generation.id)
        guard case .empty = model.state else { Issue.record("Removed preview remained visible"); return }
        #expect(model.pendingImageDeletionCount == 1)
        #expect(model.cleanupStatusError == nil)
        await studio.setPendingImageDeletionCount(0)
        await model.refreshCleanupStatus()
        #expect(model.pendingImageDeletionCount == 0)
        #expect(!model.isCheckingCleanup)
    }

    @Test("Deletion protects a source while another variation uses it")
    func preservesDependentSource() async throws {
        let studio = MockStudioRepository()
        let parent = StudioGeneration(id: UUID(), userID: SampleData.userID, referenceImagePath: "", status: .complete, resultImagePath: "parent")
        let child = StudioGeneration(id: UUID(), userID: SampleData.userID, referenceImagePath: "parent", status: .complete, resultImagePath: "child")
        await studio.seed(parent)
        await studio.seed(child)
        let model = StudioHomeViewModel(studioRepository: studio, imageURLResolver: MockClosetImageURLResolver())
        await model.onAppear()
        await model.deleteGeneration(id: parent.id)
        #expect(model.deletionError?.contains("variation") == true)
        #expect(try await studio.fetchGeneration(id: parent.id).id == parent.id)
        model.clearDeletionError()
        await model.deleteGeneration(id: child.id)
        await model.deleteGeneration(id: parent.id)
        guard case .empty = model.state else { Issue.record("Dependent removals failed"); return }
    }

    @Test("Deleting a saved estimate removes its collection membership")
    func removesSavedMembership() async throws {
        let studio = MockStudioRepository()
        let generation = StudioGeneration(id: UUID(), userID: SampleData.userID, referenceImagePath: "", status: .complete, resultImagePath: "result")
        await studio.seed(generation)
        let collection = try await studio.createLookbook(name: "Favorites")
        try await studio.saveGeneration(id: generation.id, to: collection.id)
        try await studio.deleteGeneration(id: generation.id)
        #expect(try await studio.fetchLookbookGenerations(lookbookID: collection.id, offset: 0, limit: 20).isEmpty)
    }

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
