import Foundation
import Observation

@MainActor @Observable
final class StudioLookbooksViewModel {
    private(set) var lookbooks: [StudioLookbook] = []
    private(set) var savedIDs: Set<UUID> = []
    private(set) var isLoading = true
    private(set) var isLoadingMore = false
    private(set) var isMutating = false
    private(set) var hasMore = false
    private(set) var error: String?
    let generationID: UUID?
    private let repository: StudioRepository
    private var offset = 0
    private var revision = 0
    private var hasLoadedMembership = false
    static let pageSize = 20

    init(repository: StudioRepository, generationID: UUID? = nil) {
        self.repository = repository
        self.generationID = generationID
    }

    var canSave: Bool { !isMutating && !isLoading && hasLoadedMembership }

    func load(reset: Bool = true) async {
        guard !isMutating else { return }
        guard reset || (hasMore && !isLoadingMore && !isLoading && !isMutating) else { return }
        if reset { revision += 1; isLoading = true; isLoadingMore = false } else { isLoadingMore = true }
        let request = revision
        let start = reset ? 0 : offset
        error = nil
        defer {
            if request == revision { isLoading = false; isLoadingMore = false }
        }
        do {
            let page = try await repository.fetchLookbooks(offset: start, limit: Self.pageSize)
            var membership = savedIDs
            if reset, let generationID {
                membership = try await repository.fetchSavedLookbookIDs(generationID: generationID)
            }
            guard request == revision else { return }
            savedIDs = membership
            hasLoadedMembership = true
            lookbooks = reset ? page : lookbooks + page.filter { new in !lookbooks.contains { $0.id == new.id } }
            offset = start + page.count
            hasMore = page.count == Self.pageSize
        } catch is CancellationError {
            return
        } catch {
            guard request == revision else { return }
            self.error = (error as? AstraError)?.message ?? "Couldn't load your collections. Try again."
        }
    }

    func create(name: String) async -> Bool {
        guard !isMutating && !isLoading else { return false }
        revision += 1
        isLoadingMore = false
        isMutating = true
        error = nil
        defer { isMutating = false }
        do {
            let collection = try await repository.createLookbook(name: StudioLookbook.validatedName(name))
            // Retain the newly created collection even if saving fails, so the
            // user can retry the save without creating another empty collection.
            lookbooks.insert(collection, at: 0)
            offset += 1
            if let generationID {
                try await repository.saveGeneration(id: generationID, to: collection.id)
                savedIDs.insert(collection.id)
            }
            return true
        } catch {
            self.error = (error as? AstraError)?.message ?? "Couldn't create that collection. Try again."
            return false
        }
    }

    func toggleSave(to collection: StudioLookbook) async {
        guard canSave, let generationID else { return }
        revision += 1
        isLoadingMore = false
        isMutating = true
        error = nil
        defer { isMutating = false }
        do {
            if savedIDs.contains(collection.id) {
                try await repository.removeGeneration(id: generationID, from: collection.id)
                savedIDs.remove(collection.id)
            } else {
                try await repository.saveGeneration(id: generationID, to: collection.id)
                savedIDs.insert(collection.id)
            }
        } catch {
            self.error = (error as? AstraError)?.message ?? "Couldn't update your saved look. Try again."
        }
    }

    func rename(_ collection: StudioLookbook, name: String) async {
        await mutate {
            try await self.repository.renameLookbook(id: collection.id, name: StudioLookbook.validatedName(name))
        }
    }

    func delete(_ collection: StudioLookbook) async {
        await mutate { try await self.repository.deleteLookbook(id: collection.id) }
    }

    private func mutate(_ operation: () async throws -> Void) async {
        guard !isMutating && !isLoading else { return }
        revision += 1
        isLoadingMore = false
        isMutating = true
        error = nil
        defer { isMutating = false }
        do {
            try await operation()
            isMutating = false
            await load()
        } catch {
            self.error = (error as? AstraError)?.message ?? "Couldn't update that collection. Try again."
        }
    }
}
