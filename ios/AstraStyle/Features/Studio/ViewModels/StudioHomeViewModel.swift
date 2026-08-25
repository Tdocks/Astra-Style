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
    public enum ViewState: Sendable {
        case loading
        case empty
        case loaded([StudioGeneration])
        case failed(AstraError)
    }

    public private(set) var state: ViewState = .loading
    public private(set) var imageURLs: [UUID: URL] = [:]

    private let studioRepository: StudioRepository
    private let imageURLResolver: ClosetImageURLResolving

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
        do {
            let generations = try await studioRepository.fetchGenerations()
                .filter { !$0.isDeleted }
            let paths = generations.compactMap(\.resultImagePath)
            let resolved = (try? await imageURLResolver.resolve(storagePaths: paths)) ?? [:]
            imageURLs = Dictionary(
                uniqueKeysWithValues: generations.compactMap { generation in
                    guard let path = generation.resultImagePath,
                          let url = resolved[path] else { return nil }
                    return (generation.id, url)
                }
            )
            state = generations.isEmpty ? .empty : .loaded(generations)
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }
}
