import Foundation
import Observation

@MainActor @Observable
final class StudioSavedLooksViewModel {
    private(set) var generations: [StudioGeneration] = []
    private(set) var imageURLs: [UUID: URL] = [:]
    private(set) var isLoading = true
    private(set) var isLoadingMore = false
    private(set) var isRemoving = false
    private(set) var hasMore = false
    private(set) var error: String?
    let lookbookID: UUID
    private let repository: StudioRepository
    private let resolver: ClosetImageURLResolving
    private var offset = 0
    private var revision = 0

    init(lookbookID: UUID, repository: StudioRepository, resolver: ClosetImageURLResolving) {
        self.lookbookID = lookbookID
        self.repository = repository
        self.resolver = resolver
    }

    func load(reset: Bool = true) async {
        guard shouldLoad(reset: reset) else { return }
        if reset { revision += 1; isLoading = true; isLoadingMore = false } else { isLoadingMore = true }
        let request = revision
        let start = reset ? 0 : offset
        error = nil
        defer { if request == revision { isLoading = false; isLoadingMore = false } }
        do {
            let page = try await repository.fetchLookbookGenerations(lookbookID: lookbookID, offset: start, limit: 20)
            let visible = page.filter { !$0.isDeleted && $0.status == .complete }
            let urls = (try? await resolver.resolve(storagePaths: visible.compactMap(\.resultImagePath))) ?? [:]
            guard request == revision else { return }
            offset = start + page.count
            hasMore = page.count == 20
            generations = reset ? visible : generations + visible.filter { new in !generations.contains { $0.id == new.id } }
            updateImageURLs(for: visible, resolved: urls, reset: reset)
            if hasMissingImage(visible) {
                error = "Some images couldn't load. Pull to refresh to try again."
            }
        } catch is CancellationError {
            return
        } catch {
            guard request == revision else { return }
            self.error = (error as? AstraError)?.message ?? "Couldn't load your saved looks. Try again."
        }
    }

    func remove(_ generation: StudioGeneration) async {
        guard !isRemoving && !isLoading else { return }
        isRemoving = true
        defer { isRemoving = false }
        // Any in-flight pagination must not restore a removed entry.
        revision += 1
        isLoadingMore = false
        do {
            try await repository.removeGeneration(id: generation.id, from: lookbookID)
            isRemoving = false
            await load()
        } catch { self.error = (error as? AstraError)?.message ?? "Couldn't remove that saved look. Try again." }
    }

    private func shouldLoad(reset: Bool) -> Bool {
        guard !isRemoving else { return false }
        return reset || (hasMore && !isLoadingMore && !isLoading)
    }

    private func updateImageURLs(
        for visible: [StudioGeneration],
        resolved: [String: URL],
        reset: Bool
    ) {
        if reset { imageURLs = [:] }
        for row in visible {
            if let path = row.resultImagePath, let url = resolved[path] { imageURLs[row.id] = url }
        }
    }

    private func hasMissingImage(_ visible: [StudioGeneration]) -> Bool {
        visible.contains { imageURLs[$0.id] == nil }
    }
}
