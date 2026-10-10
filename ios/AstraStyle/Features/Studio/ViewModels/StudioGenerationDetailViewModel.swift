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

    public internal(set) var state: ViewState = .loading
    public private(set) var resultImageURL: URL?
    public private(set) var exportURL: URL?
    public private(set) var exportError: String?
    public private(set) var isExporting = false
    public internal(set) var highResolutionChild: StudioGeneration?
    public internal(set) var highResolutionImageURL: URL?
    public internal(set) var highResolutionError: String?
    public internal(set) var isPreparingHighResolutionExport = false
    public internal(set) var isExportingHighResolution = false
    public internal(set) var highResolutionQuota: StudioQuota?
    public internal(set) var hasPendingHighResolutionConfirmation = false
    public internal(set) var highResolutionSubmissionUncertain = false
    public internal(set) var hasCheckedHighResolutionLineage = false
    public internal(set) var isCheckingHighResolutionLineage = false
    public var descriptionDraft = ""
    public private(set) var isSavingDescription = false
    public private(set) var descriptionError: String?
    public var pollInterval: Duration = StudioPollingPolicy.initialDelay
    public var maximumPollInterval: Duration = StudioPollingPolicy.maximumDelay
    public var maximumPollingDuration: Duration = StudioPollingPolicy.timeout

    let generationID: UUID
    let studioRepository: StudioRepository
    let imageURLResolver: ClosetImageURLResolving
    let exporter: StudioEstimateExporting

    public init(
        generationID: UUID,
        studioRepository: StudioRepository,
        imageURLResolver: ClosetImageURLResolving,
        exporter: StudioEstimateExporting
    ) {
        self.generationID = generationID
        self.studioRepository = studioRepository
        self.imageURLResolver = imageURLResolver
        self.exporter = exporter
    }

    public func prepareExport() async {
        guard !isExporting, case .loaded(let generation) = state,
              generation.status == .complete, !generation.isDeleted,
              let path = generation.resultImagePath else { return }
        isExporting = true
        exportError = nil
        exportURL = nil
        defer { isExporting = false }
        do {
            // Recheck deletion before downloading, and renew the private URL.
            let current = try await studioRepository.fetchGeneration(id: generation.id)
            guard !current.isDeleted, current.status == .complete, current.resultImagePath == path else {
                throw AstraError.validation("This estimate is no longer available.")
            }
            let signedURL = try await imageURLResolver.resolve(storagePath: path)
            exportURL = try await exporter.export(imageURL: signedURL)
        } catch is CancellationError {
            return
        } catch { exportError = (error as? AstraError)?.message ?? "Couldn't prepare this image. Try again." }
    }

    public func saveImageDescription() async -> Bool {
        guard !isSavingDescription, case .loaded(let generation) = state,
              generation.status == .complete, !generation.isDeleted else { return false }
        isSavingDescription = true
        descriptionError = nil
        defer { isSavingDescription = false }
        do {
            let updated = try await studioRepository.updateImageDescription(id: generation.id, description: descriptionDraft)
            state = .loaded(updated)
            return true
        } catch {
            descriptionError = (error as? AstraError)?.message ?? "Couldn't save the image description. Try again."
            return false
        }
    }

    public func onAppear() async {
        if case .loading = state {
            await refresh()
            return
        }
        // A detail task may be cancelled when the user leaves the screen or
        // the app backgrounds. `follow` deliberately leaves the last known
        // queued/generating value visible on cancellation, so resume status
        // reconciliation when that same detail view appears again.
        if case .loaded(let generation) = state,
           generation.status == .queued || generation.status == .generating {
            await refresh()
            return
        }
        guard !hasCheckedHighResolutionLineage,
              case .loaded(let generation) = state,
              generation.status == .complete else { return }
        await restoreExistingHighResolutionExport(sourceID: generation.id)
    }

    public func refresh() async {
        do {
            let generation = try await studioRepository.fetchGeneration(id: generationID)
            if generation.isDeleted {
                state = .failed(AstraError.server("That estimate was deleted."))
                return
            }
            await follow(generation)
            if generation.status == .complete {
                await restoreExistingHighResolutionExport(sourceID: generation.id)
            }
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
                delay = StudioPollingPolicy.nextDelay(after: delay, maximum: maximumPollInterval)
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
