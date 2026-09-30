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
    public var pollInterval: Duration = .seconds(2)
    public var maximumPollInterval: Duration = .seconds(8)
    public var maximumPollingDuration: Duration = .seconds(180)

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
        await refresh()
    }

    public func refresh() async {
        do {
            let generation = try await studioRepository.fetchGeneration(id: generationID)
            if generation.isDeleted {
                state = .failed(AstraError.server("That estimate was deleted."))
                return
            }
            await follow(generation)
        } catch let error as AstraError {
            state = .failed(error)
        } catch is CancellationError {
            return
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    public func retry() async {
        guard case .loaded(let generation) = state,
              generation.isRetryableWithoutCharge else { return }
        state = .loading
        resultImageURL = nil
        do {
            let retry = try await studioRepository.retryGeneration(id: generation.id)
            await follow(retry)
        } catch let error as AstraError {
            state = .failed(error)
        } catch is CancellationError {
            return
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    private func follow(_ initial: StudioGeneration) async {
        var generation = initial
        state = .loaded(generation)
        var delay = pollInterval
        let clock = ContinuousClock()
        let deadline = clock.now + maximumPollingDuration

        do {
            while generation.status == .queued || generation.status == .generating {
                guard clock.now < deadline else {
                    state = .failed(AstraError.network(
                        "This preview is taking longer than expected. Pull to refresh to check again."
                    ))
                    return
                }
                if delay > .zero {
                    try await Task.sleep(for: delay)
                    try Task.checkCancellation()
                }
                generation = try await studioRepository.fetchStatus(generationID: generation.id)
                if generation.isDeleted {
                    state = .failed(AstraError.server("That estimate was deleted."))
                    return
                }
                state = .loaded(generation)
                delay = min(delay + delay, maximumPollInterval)
            }

            guard generation.status == .complete, let path = generation.resultImagePath else {
                state = .loaded(generation)
                return
            }
            resultImageURL = try await imageURLResolver.resolve(storagePath: path)
        } catch let error as AstraError {
            state = .failed(error)
        } catch is CancellationError {
            return
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }
}
