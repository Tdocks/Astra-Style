//
//  StudioGenerationViewModel.swift
//  AstraStyle
//
//  Wave E: today's look (or a named outfit) on him, after terms-versioned
//  consent. No preset mall. Mock provider is the default on the server.
//

import Foundation
import Observation

@MainActor
@Observable
public final class StudioGenerationViewModel {
    public enum Phase: Sendable, Equatable {
        case preparing
        case ready
        case generating
        case complete
        case failed(AstraError)
    }

    public private(set) var phase: Phase = .preparing
    public private(set) var hasGrantedConsent = false
    public private(set) var existingReferencePath: String?
    public private(set) var pendingImageData: Data?
    public private(set) var generation: StudioGeneration?
    public private(set) var resultImageURL: URL?
    public var selectedPreset: StudioPromptPreset? = .smartCasual
    public var selectedBackground: StudioBackground = .studio
    public var selectedPose: StudioPose = .standingFront
    public var selectedFormality: FormalityLevel? = .balanced
    public var selectedSeason: Season? = StudioGenerationViewModel.currentSeason
    public var paletteText = ""
    public var preservesFace = true
    public var preservesBodyProportions = true
    public var preservesHair = true

    /// Nested paywall after the free Visualize trial. First open stays ungated.
    private(set) var quotaSummary = "Preview allowance unavailable"
    public private(set) var pendingPaywall: PaywallContext?
    public var pollInterval: Duration = .seconds(2)
    public var maximumPollInterval: Duration = .seconds(8)
    public var maximumPollingDuration: Duration = .seconds(180)

    private let outfitID: UUID?
    private let studioRepository: StudioRepository
    private let profileRepository: ProfileRepository
    private let imageURLResolver: ClosetImageURLResolving

    public init(
        outfitID: UUID?,
        studioRepository: StudioRepository,
        profileRepository: ProfileRepository,
        imageURLResolver: ClosetImageURLResolving
    ) {
        self.outfitID = outfitID
        self.studioRepository = studioRepository
        self.profileRepository = profileRepository
        self.imageURLResolver = imageURLResolver
    }

    public var canGenerate: Bool {
        hasGrantedConsent && (existingReferencePath != nil || pendingImageData != nil)
    }

    public func onAppear() async {
        guard case .preparing = phase else { return }
        if let body = try? await profileRepository.fetchBodyProfile() {
            existingReferencePath = body.appearance.referenceSelfiePaths.first
        }
        await refreshQuota()
        phase = .ready
    }

    public func grantConsent() {
        hasGrantedConsent = true
    }

    public func withdrawConsent() {
        hasGrantedConsent = false
        pendingImageData = nil
    }

    public func setPendingImage(_ data: Data) {
        pendingImageData = data
    }

    public func removePendingImage() {
        pendingImageData = nil
    }

    public func generate() async {
        guard hasGrantedConsent else {
            phase = .failed(AstraError.validation("Please confirm you have permission to use this photo before generating a preview."))
            return
        }
        phase = .generating
        resultImageURL = nil
        do {
            let path = try await resolveReferencePath()
            let request = StudioGenerationRequest(
                referenceImagePath: path,
                outfitID: outfitID,
                preset: selectedPreset,
                preserveFace: preservesFace,
                preserveBodyProportions: preservesBodyProportions,
                preserveHair: preservesHair,
                background: selectedBackground,
                pose: selectedPose,
                formality: selectedFormality,
                season: selectedSeason,
                colorPalette: Array(
                    paletteText
                        .split(separator: ",")
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .prefix(8)
                ),
                hasUserConsent: true,
                consentTermsVersion: StudioConsentTerms.currentVersion
            )
            let job = try await studioRepository.startGeneration(request)
            await refreshQuota()
            await completeGeneration(from: job)
        } catch let error as AstraError {
            phase = .failed(error)
            if error.category == .rateLimited && error.message.contains("free visual") {
                pendingPaywall = .studioQuota
            }
        } catch {
            phase = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    func refreshQuota() async {
        do { quotaSummary = try await studioRepository.fetchQuota().summary }
        catch { quotaSummary = "Couldn't load your preview allowance. Try again." }
    }

    public func clearPendingPaywall() {
        pendingPaywall = nil
    }

    public func retry() async {
        guard case .failed(let previousError) = phase else { return }
        guard let generation else {
            guard previousError.isRetryable else { return }
            await generate()
            return
        }

        phase = .generating
        resultImageURL = nil
        do {
            if generation.status == .complete {
                try await resolveCompletedImage(generation)
                phase = .complete
                return
            }

            let job: StudioGeneration
            if generation.status == .failed {
                guard generation.isRetryableWithoutCharge else {
                    phase = .failed(previousError)
                    return
                }
                job = try await studioRepository.retryGeneration(id: generation.id)
            } else {
                job = generation
            }
            await completeGeneration(from: job)
        } catch let error as AstraError {
            phase = .failed(error)
        } catch {
            phase = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    private func completeGeneration(from initialJob: StudioGeneration) async {
        do {
            let job = try await pollUntilTerminal(initialJob)
            generation = job
            guard job.status == .complete else {
                phase = .failed(AstraError.provider(job.errorMessage ?? "That preview didn't come through."))
                return
            }
            try await resolveCompletedImage(job)
            phase = .complete
        } catch let error as AstraError {
            phase = .failed(error)
        } catch is CancellationError {
            phase = .failed(.cancelled)
        } catch {
            phase = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    private func pollUntilTerminal(_ initialJob: StudioGeneration) async throws -> StudioGeneration {
        var job = initialJob
        generation = job
        var delay = pollInterval
        let clock = ContinuousClock()
        let deadline = clock.now + maximumPollingDuration

        while job.status == .queued || job.status == .generating {
            guard clock.now < deadline else {
                throw AstraError.network(
                    "This preview is taking longer than expected. You can check again from Style Studio."
                )
            }
            if delay > .zero {
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
            }
            job = try await studioRepository.fetchStatus(generationID: job.id)
            generation = job
            delay = min(delay + delay, maximumPollInterval)
        }
        return job
    }

    private func resolveCompletedImage(_ job: StudioGeneration) async throws {
        guard let resultPath = job.resultImagePath else {
            throw AstraError.server("Your preview finished, but its image is missing. Please try again.")
        }
        do {
            resultImageURL = try await imageURLResolver.resolve(storagePath: resultPath)
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.network("Your preview is saved, but its image couldn't load. Please try again.")
        }
    }

    private func resolveReferencePath() async throws -> String {
        if let existingReferencePath { return existingReferencePath }
        guard let pendingImageData else {
            throw AstraError.validation("Add a photo of you first.")
        }
        return try await profileRepository.uploadReferenceImage(pendingImageData)
    }

    private static var currentSeason: Season {
        switch Calendar.current.component(.month, from: .now) {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .fall
        default: .winter
        }
    }
}
