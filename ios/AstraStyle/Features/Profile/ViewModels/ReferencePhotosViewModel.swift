//
//  ReferencePhotosViewModel.swift
//  AstraStyle
//
//  Owns the user's optional Style Studio reference photos and the previews
//  derived from them so privacy deletion is one confirmed, coordinated action.
//

import Foundation
import Observation

public struct SavedReferencePhoto: Identifiable, Sendable {
    public let path: String
    public let previewCount: Int
    public let isUsedByActivePreview: Bool

    public var id: String { path }

    public init(path: String, previewCount: Int, isUsedByActivePreview: Bool) {
        self.path = path
        self.previewCount = previewCount
        self.isUsedByActivePreview = isUsedByActivePreview
    }
}

@MainActor
@Observable
public final class ReferencePhotosViewModel {
    public enum State: Sendable {
        case loading
        case loaded([SavedReferencePhoto])
        case empty
        case failed(String)
    }

    public private(set) var state: State = .loading
    public private(set) var imageURLs: [String: URL] = [:]
    public private(set) var deletingPaths: Set<String> = []
    public var deletionError: String?
    public private(set) var pendingImageDeletionCount = 0
    public private(set) var removalStatusError: String?
    public private(set) var isCheckingRemoval = false

    private let profileRepository: ProfileRepository
    private let studioRepository: StudioRepository
    private let imageURLResolver: ClosetImageURLResolving
    private var hasLoaded = false

    public init(
        profileRepository: ProfileRepository,
        studioRepository: StudioRepository,
        imageURLResolver: ClosetImageURLResolving
    ) {
        self.profileRepository = profileRepository
        self.studioRepository = studioRepository
        self.imageURLResolver = imageURLResolver
    }

    public func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh()
    }

    public func refresh() async {
        await refreshRemovalStatus()
        do {
            let bodyProfile = try await profileRepository.fetchBodyProfile()
            var seenPaths: Set<String> = []
            let paths = (bodyProfile?.appearance.referenceSelfiePaths ?? [])
                .filter { seenPaths.insert($0).inserted }
            guard !paths.isEmpty else {
                imageURLs = [:]
                state = .empty
                return
            }

            let generations = try await fetchVisibleGenerations()
            let photos = try paths.map { path in
                let matches = try ReferencePhotoPreviewGraph.deletionOrder(sourcePath: path, generations: generations)
                return SavedReferencePhoto(
                    path: path,
                    previewCount: matches.filter { !$0.isDeleted }.count,
                    isUsedByActivePreview: matches.contains(where: Self.isActive)
                )
            }
            let resolved = (try? await imageURLResolver.resolve(storagePaths: paths)) ?? [:]
            imageURLs = resolved
            state = .loaded(photos)
        } catch let error as AstraError {
            state = .failed(error.message)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func deleteReferencePhoto(path: String) async {
        guard !deletingPaths.contains(path),
              case .loaded(let photos) = state,
              photos.contains(where: { $0.path == path }) else { return }
        deletingPaths.insert(path)
        defer { deletingPaths.remove(path) }

        do {
            try await profileRepository.deleteReferenceImage(path: path)
            imageURLs[path] = nil
            let remaining = photos.filter { $0.path != path }
            state = remaining.isEmpty ? .empty : .loaded(remaining)
            await refreshRemovalStatus()
        } catch let error as AstraError {
            deletionError = error.message
        } catch {
            deletionError = error.localizedDescription
        }
    }

    public func clearDeletionError() {
        deletionError = nil
    }

    public func refreshRemovalStatus() async {
        guard !isCheckingRemoval else { return }
        isCheckingRemoval = true
        defer { isCheckingRemoval = false }
        do {
            pendingImageDeletionCount = try await studioRepository.fetchPendingImageDeletionCount()
            removalStatusError = nil
        } catch {
            removalStatusError = "Couldn't check image removal. Please try again."
        }
    }

    private func fetchVisibleGenerations() async throws -> [StudioGeneration] {
        // A single Data API select is capped. A reference's descendants can
        // span gallery pages, so never treat the first page as its whole graph.
        let pageSize = 100
        var generations: [StudioGeneration] = []
        var offset = 0
        while true {
            let page = try await studioRepository.fetchGenerations(offset: offset, limit: pageSize)
            generations.append(contentsOf: page)
            guard page.count == pageSize else { return generations }
            offset += pageSize
        }
    }

    private static func isActive(_ generation: StudioGeneration) -> Bool {
        generation.status == .queued || generation.status == .generating
    }
}

/// Counts every reachable variation and orders children before their sources.
/// The server still validates each deletion; this graph is not an authorization
/// boundary or a replacement for an atomic server-owned reference cascade.
enum ReferencePhotoPreviewGraph {
    nonisolated static func deletionOrder(sourcePath: String, generations: [StudioGeneration]) throws -> [StudioGeneration] {
        let visible = generations.filter { !$0.isDeleted }
        let bySource = Dictionary(grouping: visible, by: \.referenceImagePath)
        var visited: Set<UUID> = []
        var ancestors: Set<UUID> = []
        var ordered: [StudioGeneration] = []

        func visit(_ generation: StudioGeneration) throws {
            guard !ancestors.contains(generation.id) else {
                throw AstraError.validation("These previews have an invalid source chain. Please try again later.")
            }
            guard visited.insert(generation.id).inserted else { return }
            ancestors.insert(generation.id)
            if let result = generation.resultImagePath, !result.isEmpty {
                for child in bySource[result] ?? [] { try visit(child) }
            }
            ancestors.remove(generation.id)
            ordered.append(generation)
        }

        for root in bySource[sourcePath] ?? [] { try visit(root) }
        return ordered
    }
}
