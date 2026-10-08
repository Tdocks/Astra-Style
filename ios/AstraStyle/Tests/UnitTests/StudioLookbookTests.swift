import Foundation
import Testing
@testable import AstraStyle

@MainActor @Suite("Private Studio collections")
struct StudioLookbookTests {
    private func fixture(status: StudioGenerationStatus = .complete, deleted: Bool = false) -> StudioGeneration {
        StudioGeneration(id: UUID(), userID: SampleData.userID, referenceImagePath: "", status: status,
                         resultImagePath: "users/result.png", deletedAt: deleted ? .now : nil)
    }

    @Test("Names trim whitespace and match the database scalar limit")
    func names() throws {
        #expect(try StudioLookbook.validatedName("  Everyday\n") == "Everyday")
        #expect(throws: AstraError.self) { try StudioLookbook.validatedName(" \n ") }
        #expect(throws: AstraError.self) { try StudioLookbook.validatedName(String(repeating: "x", count: 81)) }
        #expect(throws: AstraError.self) { try StudioLookbook.validatedName(String(repeating: "👨‍👩‍👧‍👦", count: 20)) }
        #expect(try StudioLookbook.validatedName(String(repeating: "x", count: 80)).count == 80)
    }

    @Test("Creating from an estimate saves it and duplicate saves stay idempotent")
    func saveAndRemove() async throws {
        let repository = MockStudioRepository()
        let generation = fixture()
        await repository.seed(generation)
        let model = StudioLookbooksViewModel(repository: repository, generationID: generation.id)
        await model.load()
        #expect(await model.create(name: "Everyday"))
        let book = try #require(model.lookbooks.first)
        #expect(model.savedIDs == [book.id])
        try await repository.saveGeneration(id: generation.id, to: book.id)
        #expect(try await repository.fetchLookbookGenerations(lookbookID: book.id, offset: 0, limit: 20).count == 1)
        await model.toggleSave(to: book)
        #expect(model.savedIDs.isEmpty)
        #expect(try await repository.fetchLookbookGenerations(lookbookID: book.id, offset: 0, limit: 20).isEmpty)
        #expect(try await repository.fetchGeneration(id: generation.id).status == .complete)
        await model.toggleSave(to: book)
        #expect(model.savedIDs.contains(book.id))
    }

    @Test("A failed initial save keeps the created collection for a retry")
    func retrySave() async throws {
        let repository = MockStudioRepository()
        let generation = fixture()
        await repository.seed(generation)
        await repository.failNextCollectionSave()
        let model = StudioLookbooksViewModel(repository: repository, generationID: generation.id)
        await model.load()
        #expect(!(await model.create(name: "Work")))
        #expect(model.error != nil)
        #expect(model.lookbooks.count == 1)
        #expect(model.savedIDs.isEmpty)
        let book = try #require(model.lookbooks.first)
        await model.toggleSave(to: book)
        #expect(model.savedIDs == [book.id])
        #expect(model.error == nil)
        #expect(try await repository.fetchLookbooks(offset: 0, limit: 20).count == 1)
    }

    @Test("Collection list paginates, renames and removes without deleting estimates")
    func collectionLifecycle() async throws {
        let repository = MockStudioRepository()
        for index in 0..<25 { _ = try await repository.createLookbook(name: "Collection \(index)") }
        let model = StudioLookbooksViewModel(repository: repository)
        await model.load()
        #expect(model.lookbooks.count == 20 && model.hasMore)
        await model.load(reset: false)
        #expect(model.lookbooks.count == 25 && !model.hasMore)
        let book = try #require(model.lookbooks.first)
        await model.rename(book, name: "New name")
        #expect(model.lookbooks.first { $0.id == book.id }?.name == "New name")
        await model.delete(book)
        #expect(!model.lookbooks.contains { $0.id == book.id })
    }

    @Test("Saved looks paginate and removal retains the original generation")
    func savedLookPagination() async throws {
        let repository = MockStudioRepository()
        let book = try await repository.createLookbook(name: "Everyday")
        for _ in 0..<25 {
            let generation = fixture()
            await repository.seed(generation)
            try await repository.saveGeneration(id: generation.id, to: book.id)
        }
        let model = StudioSavedLooksViewModel(lookbookID: book.id, repository: repository, resolver: MockClosetImageURLResolver())
        await model.load()
        #expect(model.generations.count == 20 && model.hasMore)
        await model.load(reset: false)
        #expect(model.generations.count == 25 && !model.hasMore)
        let removed = try #require(model.generations.first)
        await model.remove(removed)
        #expect(!model.generations.contains { $0.id == removed.id })
        #expect(try await repository.fetchGeneration(id: removed.id).status == .complete)
    }

    @Test("Signing failures preserve saved looks and expose recovery")
    func imageFailure() async throws {
        let repository = MockStudioRepository()
        let book = try await repository.createLookbook(name: "Date night")
        let generation = fixture()
        await repository.seed(generation)
        try await repository.saveGeneration(id: generation.id, to: book.id)
        let model = StudioSavedLooksViewModel(lookbookID: book.id, repository: repository, resolver: LookbookSigningFailure())
        await model.load()
        #expect(model.generations.count == 1)
        #expect(model.error != nil && model.imageURLs.isEmpty)
    }

    @Test("Unfinished, deleted and other-user estimates cannot be saved")
    func eligibility() async throws {
        let repository = MockStudioRepository()
        let book = try await repository.createLookbook(name: "Work")
        var peer = fixture(); peer.userID = UUID()
        for generation in [fixture(status: .queued), fixture(deleted: true), peer] {
            await repository.seed(generation)
            await #expect(throws: AstraError.self) { try await repository.saveGeneration(id: generation.id, to: book.id) }
        }
    }
}

private struct LookbookSigningFailure: ClosetImageURLResolving {
    func resolve(storagePath: String) async throws -> URL { throw AstraError.network("Offline") }
    func resolve(storagePaths: [String]) async throws -> [String: URL] { throw AstraError.network("Offline") }
}
