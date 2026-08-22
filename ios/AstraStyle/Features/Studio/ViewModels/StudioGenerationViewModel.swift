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
    public var pollInterval: Duration = .milliseconds(400)

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
                hasUserConsent: true,
                consentTermsVersion: StudioConsentTerms.currentVersion
            )
            var job = try await studioRepository.startGeneration(request)
            while job.status == .queued || job.status == .generating {
                if pollInterval != .zero {
                    try await Task.sleep(for: pollInterval)
                }
                job = try await studioRepository.fetchStatus(generationID: job.id)
            }
            generation = job
            if job.status == .complete, let resultPath = job.resultImagePath {
                resultImageURL = try? await imageURLResolver.resolve(storagePath: resultPath)
                phase = .complete
            } else {
                phase = .failed(AstraError.provider(job.errorMessage ?? "That preview didn't come through."))
            }
        } catch let error as AstraError {
            phase = .failed(error)
        } catch {
            phase = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    public func retry() async {
        await generate()
    }

    private func resolveReferencePath() async throws -> String {
        if let existingReferencePath { return existingReferencePath }
        guard let pendingImageData else {
            throw AstraError.validation("Add a photo of you first.")
        }
        return try await profileRepository.uploadReferenceImage(pendingImageData)
    }
}
