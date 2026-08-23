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

    private let studioRepository: StudioRepository

    public init(studioRepository: StudioRepository) {
        self.studioRepository = studioRepository
    }

    public func onAppear() async {
        guard case .loading = state else { return }
        await refresh()
    }

    public func refresh() async {
        do {
            let generations = try await studioRepository.fetchGenerations()
                .filter { !$0.isDeleted }
            state = generations.isEmpty ? .empty : .loaded(generations)
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }
}
