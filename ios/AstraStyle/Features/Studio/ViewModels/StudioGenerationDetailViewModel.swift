//
//  StudioGenerationDetailViewModel.swift
//  AstraStyle
//

import Foundation
import Observation

@MainActor
@Observable
public final class StudioGenerationDetailViewModel {
    public enum ViewState: Sendable {
        case loading
        case loaded(StudioGeneration)
        case failed(AstraError)
    }

    public private(set) var state: ViewState = .loading
    public private(set) var resultImageURL: URL?

    private let generationID: UUID
    private let studioRepository: StudioRepository
    private let imageURLResolver: ClosetImageURLResolving

    public init(
        generationID: UUID,
        studioRepository: StudioRepository,
        imageURLResolver: ClosetImageURLResolving
    ) {
        self.generationID = generationID
        self.studioRepository = studioRepository
        self.imageURLResolver = imageURLResolver
    }

    public func onAppear() async {
        guard case .loading = state else { return }
        do {
            let generation = try await studioRepository.fetchGeneration(id: generationID)
            if generation.isDeleted {
                state = .failed(AstraError.server("That estimate was deleted."))
                return
            }
            state = .loaded(generation)
            if let path = generation.resultImagePath {
                resultImageURL = try? await imageURLResolver.resolve(storagePath: path)
            }
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }
}
