//
//  LiveStudioRepository.swift
//  AstraStyle
//
//  `studio_generations` reads go through Postgrest; starting a job and
//  polling status are orchestration calls (spec §14 `studio/generate`,
//  `studio/status/:id`) since they invoke `ImageGenerationProvider`
//  (spec §8) and enforce the queueing/rate-limit/cost controls in spec §13.
//

import Foundation
import Supabase

public final class LiveStudioRepository: StudioRepository, @unchecked Sendable {
    private let apiClient: AstraAPIClient
    private let supabase: SupabaseClient

    public init(apiClient: AstraAPIClient, supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current)) {
        self.apiClient = apiClient
        self.supabase = supabase
    }

    public func fetchGenerations() async throws -> [StudioGeneration] {
        do {
            return try await supabase.from("studio_generations")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            throw AstraError.network("Couldn't load your Style Studio history.")
        }
    }

    public func fetchGeneration(id: UUID) async throws -> StudioGeneration {
        do {
            return try await supabase.from("studio_generations").select().eq("id", value: id).single().execute().value
        } catch {
            throw AstraError.server("Couldn't load that generation.")
        }
    }

    public func startGeneration(_ request: StudioGenerationRequest) async throws -> StudioGeneration {
        guard request.hasUserConsent else {
            throw AstraError.validation("Please confirm you have permission to use this photo before generating a preview.")
        }
        guard request.consentTermsVersion == StudioConsentTerms.currentVersion else {
            throw AstraError.validation("Those consent terms are out of date. Read them again before generating.")
        }
        return try await apiClient.send(.generateStudio, body: StudioGenerateBody(request), as: StudioGeneration.self)
    }

    public func fetchStatus(generationID: UUID) async throws -> StudioGeneration {
        try await apiClient.send(.studioStatus(id: generationID), as: StudioGeneration.self)
    }

    public func retryGeneration(id: UUID) async throws -> StudioGeneration {
        struct Body: Encodable, Sendable {
            let retryOf: UUID
            enum CodingKeys: String, CodingKey { case retryOf = "retry_of" }
        }
        return try await apiClient.send(.generateStudio, body: Body(retryOf: id), as: StudioGeneration.self)
    }

    public func deleteGeneration(id: UUID) async throws {
        do {
            try await supabase.from("studio_generations").delete().eq("id", value: id).execute()
        } catch {
            throw AstraError.network("Couldn't delete that generation while offline.")
        }
    }
}

private struct StudioGenerateBody: Encodable, Sendable {
    let referenceImagePath: String
    let outfitID: UUID?
    let adHocItemIDs: [UUID]
    let preset: StudioPromptPreset?
    let preserveFace: Bool
    let preserveBodyProportions: Bool
    let preserveHair: Bool
    let background: StudioBackground
    let pose: StudioPose
    let formality: FormalityLevel?
    let season: Season?
    let colorPalette: [String]
    let consent: StudioConsentAttestation

    init(_ request: StudioGenerationRequest) {
        referenceImagePath = request.referenceImagePath
        outfitID = request.outfitID
        adHocItemIDs = request.adHocItemIDs
        preset = request.preset
        preserveFace = request.preserveFace
        preserveBodyProportions = request.preserveBodyProportions
        preserveHair = request.preserveHair
        background = request.background
        pose = request.pose
        formality = request.formality
        season = request.season
        colorPalette = request.colorPalette
        consent = StudioConsentAttestation(
            acknowledged: request.hasUserConsent,
            termsVersion: request.consentTermsVersion
        )
    }

    enum CodingKeys: String, CodingKey {
        case referenceImagePath = "reference_image_path"
        case outfitID = "outfit_id"
        case adHocItemIDs = "ad_hoc_item_ids"
        case preset
        case preserveFace = "preserve_face"
        case preserveBodyProportions = "preserve_body_proportions"
        case preserveHair = "preserve_hair"
        case background
        case pose
        case formality
        case season
        case colorPalette = "color_palette"
        case consent
    }
}
