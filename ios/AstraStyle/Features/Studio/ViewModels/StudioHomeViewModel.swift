//
//  StudioHomeViewModel.swift
//  AstraStyle
//
//  Lists this user's Style Studio generations. Generate stays a modal.
//

import Foundation
import Observation

@MainActor
@Observable
public final class StudioHomeViewModel {
    public static let pageSize = 20
    public enum ViewState: Sendable {
        case loading
        case empty
        case loaded([StudioGeneration])
        case failed(AstraError)
    }

    public private(set) var state: ViewState = .loading
    public private(set) var imageURLs: [UUID: URL] = [:]
    public private(set) var deletingIDs: Set<UUID> = []
    public var deletionError: String?
    public private(set) var isLoadingMore = false
    public private(set) var hasMore = false
    public private(set) var paginationError: String?

    private let studioRepository: StudioRepository
    private let imageURLResolver: ClosetImageURLResolving
    private var serverOffset = 0
    private var requestGeneration = 0

    public init(
        studioRepository: StudioRepository,
        imageURLResolver: ClosetImageURLResolving
    ) {
        self.studioRepository = studioRepository
        self.imageURLResolver = imageURLResolver
    }

    public func onAppear() async {
        guard case .loading = state else { return }
        await refresh()
    }

    public func refresh() async {
        requestGeneration += 1
        let currentRequest = requestGeneration
        serverOffset = 0
        isLoadingMore = false
        hasMore = false
        paginationError = nil
        do {
            let page = try await studioRepository.fetchGenerations(offset: 0, limit: Self.pageSize)
            guard currentRequest == requestGeneration else { return }
            serverOffset = page.count
            hasMore = page.count == Self.pageSize
            let generations = page.filter { !$0.isDeleted }
            let paths = generations.compactMap(\.resultImagePath)
            let resolved = (try? await imageURLResolver.resolve(storagePaths: paths)) ?? [:]
            guard currentRequest == requestGeneration else { return }
            imageURLs = Dictionary(
                uniqueKeysWithValues: generations.compactMap { generation in
                    guard let path = generation.resultImagePath,
                          let url = resolved[path] else { return nil }
                    return (generation.id, url)
                }
            )
            state = generations.isEmpty ? .empty : .loaded(generations)
        } catch let error as AstraError {
            guard currentRequest == requestGeneration else { return }
            state = .failed(error)
        } catch {
            guard currentRequest == requestGeneration else { return }
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    public func loadMoreIfNeeded(after generationID: UUID) async {
        guard case .loaded(let generations) = state,
              let index = generations.firstIndex(where: { $0.id == generationID }),
              index >= max(0, generations.count - 4) else { return }
        await loadNextPage()
    }

    public func loadNextPage() async {
        guard hasMore, !isLoadingMore else { return }
        guard case .loaded(let existing) = state else { return }

        isLoadingMore = true
        let currentRequest = requestGeneration
        defer {
            if currentRequest == requestGeneration {
                isLoadingMore = false
            }
        }

        do {
            let page = try await studioRepository.fetchGenerations(
                offset: serverOffset,
                limit: Self.pageSize
            )
            guard currentRequest == requestGeneration else { return }
            serverOffset += page.count
            hasMore = page.count == Self.pageSize
            paginationError = nil

            let existingIDs = Set(existing.map(\.id))
            let additions = page.filter { !$0.isDeleted && !existingIDs.contains($0.id) }
            let paths = additions.compactMap(\.resultImagePath)
            let resolved = (try? await imageURLResolver.resolve(storagePaths: paths)) ?? [:]
            guard currentRequest == requestGeneration else { return }
            for generation in additions {
                if let path = generation.resultImagePath, let url = resolved[path] {
                    imageURLs[generation.id] = url
                }
            }

            let combined = existing + additions
            state = combined.isEmpty ? .empty : .loaded(combined)
        } catch let error as AstraError {
            if currentRequest == requestGeneration {
                paginationError = error.message
            }
        } catch {
            if currentRequest == requestGeneration {
                paginationError = error.localizedDescription
            }
        }
    }

    public func deleteGeneration(id: UUID) async {
        guard !deletingIDs.contains(id),
              case .loaded(let generations) = state,
              let generation = generations.first(where: { $0.id == id }) else { return }
        guard generation.status == .complete || generation.status == .failed else {
            deletionError = String(localized: "Wait for this preview to finish before deleting it.")
            return
        }

        deletingIDs.insert(id)
        defer { deletingIDs.remove(id) }

        do {
            try await studioRepository.deleteGeneration(id: id)
            imageURLs[id] = nil
            serverOffset = max(0, serverOffset - 1)
            guard case .loaded(let currentGenerations) = state else { return }
            let remaining = currentGenerations.filter { $0.id != id }
            if remaining.isEmpty, hasMore {
                await refresh()
            } else {
                state = remaining.isEmpty ? .empty : .loaded(remaining)
            }
        } catch let error as AstraError {
            deletionError = error.message
        } catch {
            deletionError = error.localizedDescription
        }
    }

    public func clearDeletionError() {
        deletionError = nil
    }

    public func clearPaginationError() {
        paginationError = nil
    }
}
