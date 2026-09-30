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

            let generations = try await studioRepository.fetchGenerations()
                .filter { paths.contains($0.referenceImagePath) }
            let photos = paths.map { path in
                let matches = generations.filter { $0.referenceImagePath == path }
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
            try await deletePreviewsUsing(path: path)
            try await profileRepository.deleteReferenceImage(path: path)
            imageURLs[path] = nil
            let remaining = photos.filter { $0.path != path }
            state = remaining.isEmpty ? .empty : .loaded(remaining)
        } catch let error as AstraError {
            deletionError = error.message
        } catch {
            deletionError = error.localizedDescription
        }
    }

    public func clearDeletionError() {
        deletionError = nil
    }

    private func deletePreviewsUsing(path: String) async throws {
        let matches = try await studioRepository.fetchGenerations()
            .filter { $0.referenceImagePath == path }
        guard !matches.contains(where: Self.isActive) else {
            throw AstraError.validation("A preview is in progress. Try again when it finishes.")
        }
        for generation in matches {
            try await studioRepository.deleteGeneration(id: generation.id)
        }
    }

    private static func isActive(_ generation: StudioGeneration) -> Bool {
        generation.status == .queued || generation.status == .generating
    }
}
