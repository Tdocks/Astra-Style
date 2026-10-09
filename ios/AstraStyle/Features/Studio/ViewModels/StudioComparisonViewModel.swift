import Foundation
import Observation

@MainActor
@Observable
final class StudioComparisonViewModel {
    enum State {
        case loading
        case loaded([StudioGeneration])
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var imageURLs: [String: URL] = [:]
    private(set) var imageError: String?
    private let generationIDs: [UUID]
    private let repository: StudioRepository
    private let resolver: ClosetImageURLResolving
    private var revision = 0

    init(generationIDs: [UUID], repository: StudioRepository, resolver: ClosetImageURLResolving) {
        self.generationIDs = generationIDs
        self.repository = repository
        self.resolver = resolver
    }

    func load() async {
        revision += 1
        let request = revision
        guard hasValidSelection else {
            state = .failed("Choose one or two different completed previews to compare.")
            return
        }
        state = .loading
        imageError = nil
        imageURLs = [:]
        do {
            var generations: [StudioGeneration] = []
            for id in generationIDs {
                let generation = try await repository.fetchGeneration(id: id)
                guard !generation.isDeleted,
                      generation.status == .complete,
                      generation.resultImagePath != nil else {
                    throw AstraError.validation(
                        "One of these previews is unavailable. Choose completed previews from Style Studio."
                    )
                }
                generations.append(generation)
            }
            guard request == revision else { return }
            let paths = Set(generations.flatMap { imagePaths(for: $0) })
            let (resolved, failedToResolve) = try await resolveImages(paths)
            guard request == revision else { return }
            imageError = failedToResolve ? "Some images couldn't load. Pull to refresh to try again." : nil
            imageURLs = resolved
            state = .loaded(generations)
        } catch is CancellationError {
            return
        } catch {
            guard request == revision else { return }
            state = .failed((error as? AstraError)?.message ?? "Couldn't load these previews. Try again.")
        }
    }

    private var hasValidSelection: Bool {
        (1...2).contains(generationIDs.count) && Set(generationIDs).count == generationIDs.count
    }

    private func imagePaths(for generation: StudioGeneration) -> [String] {
        [generation.resultImagePath, generation.referenceImagePath.isEmpty ? nil : generation.referenceImagePath]
            .compactMap { $0 }
    }

    private func resolveImages(_ paths: Set<String>) async throws -> ([String: URL], Bool) {
        var resolved: [String: URL] = [:]
        var failedToResolve = false
        for path in paths {
            try Task.checkCancellation()
            do {
                resolved[path] = try await resolver.resolve(storagePath: path)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failedToResolve = true
            }
        }
        return (resolved, failedToResolve)
    }
}
