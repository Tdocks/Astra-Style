import Foundation
import Testing
@testable import AstraStyle

@MainActor
@Suite("Studio comparison")
struct StudioComparisonViewModelTests {
    private func fixture(status: StudioGenerationStatus = .complete, deleted: Bool = false) -> StudioGeneration {
        let id = UUID()
        return StudioGeneration(id: id, userID: SampleData.userID,
            referenceImagePath: "users/reference.jpg", status: status,
            resultImagePath: "users/\(id)/result.png", deletedAt: deleted ? .now : nil)
    }

    @Test("One preview resolves original and generated image")
    func beforeAfter() async {
        let repository = MockStudioRepository()
        let generation = fixture()
        await repository.seed(generation)
        let model = StudioComparisonViewModel(generationIDs: [generation.id], repository: repository, resolver: MockClosetImageURLResolver())
        await model.load()
        guard case .loaded(let rows) = model.state else { Issue.record("Expected loaded comparison"); return }
        #expect(rows.count == 1)
        #expect(model.imageURLs.count == 2)
        #expect(model.imageError == nil)
    }

    @Test("Two previews retain selected ordering")
    func twoLooks() async {
        let repository = MockStudioRepository()
        let firstGeneration = fixture()
        let secondGeneration = fixture()
        await repository.seed(firstGeneration)
        await repository.seed(secondGeneration)
        let model = StudioComparisonViewModel(
            generationIDs: [secondGeneration.id, firstGeneration.id],
            repository: repository,
            resolver: MockClosetImageURLResolver()
        )
        await model.load()
        guard case .loaded(let rows) = model.state else { Issue.record("Expected loaded comparison"); return }
        #expect(rows.map(\.id) == [secondGeneration.id, firstGeneration.id])
        #expect(model.imageURLs.count == 3)
    }

    @Test("Invalid selections are recoverable errors", arguments: [0, 3])
    func invalidCounts(_ count: Int) async {
        let model = StudioComparisonViewModel(generationIDs: (0..<count).map { _ in UUID() }, repository: MockStudioRepository(), resolver: MockClosetImageURLResolver())
        await model.load()
        guard case .failed = model.state else { Issue.record("Invalid count accepted"); return }
    }

    @Test("Duplicate IDs are rejected")
    func duplicates() async {
        let id = UUID()
        let model = StudioComparisonViewModel(generationIDs: [id, id], repository: MockStudioRepository(), resolver: MockClosetImageURLResolver())
        await model.load()
        guard case .failed = model.state else { Issue.record("Duplicate accepted"); return }
    }

    @Test("Incomplete and deleted previews cannot be compared")
    func unavailable() async {
        for generation in [fixture(status: .queued), fixture(status: .failed), fixture(deleted: true)] {
            let repository = MockStudioRepository()
            await repository.seed(generation)
            let model = StudioComparisonViewModel(generationIDs: [generation.id], repository: repository, resolver: MockClosetImageURLResolver())
            await model.load()
            guard case .failed = model.state else { Issue.record("Unavailable preview accepted"); return }
        }
    }

    @Test("Image signing failure preserves comparison and exposes retry")
    func signingFailure() async {
        let repository = MockStudioRepository()
        let generation = fixture()
        await repository.seed(generation)
        let model = StudioComparisonViewModel(generationIDs: [generation.id], repository: repository, resolver: FailingComparisonResolver())
        await model.load()
        guard case .loaded = model.state else { Issue.record("Comparison should remain visible"); return }
        #expect(model.imageError != nil)
        #expect(model.imageURLs.isEmpty)
    }
}

private struct FailingComparisonResolver: ClosetImageURLResolving {
    func resolve(storagePath: String) async throws -> URL { throw AstraError.network("Offline") }
    func resolve(storagePaths: [String]) async throws -> [String: URL] { throw AstraError.network("Offline") }
}
