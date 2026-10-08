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

    public func fetchGenerations(offset: Int, limit: Int) async throws -> [StudioGeneration] {
        guard offset >= 0, limit > 0 else {
            throw AstraError.validation("That Style Studio page is invalid.")
        }
        do {
            return try await supabase.from("studio_generations")
                .select()
                .is("deleted_at", value: nil)
                .order("created_at", ascending: false)
                .order("id", ascending: false)
                .range(from: offset, to: offset + limit - 1)
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
        guard request.inspirationMode != nil || request.hasUserConsent else {
            throw AstraError.validation("Please confirm you have permission to use this photo before generating a preview.")
        }
        guard request.inspirationMode != nil || request.consentTermsVersion == StudioConsentTerms.currentVersion else {
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
        let generation = try await fetchGeneration(id: id)
        guard generation.status == .complete || generation.status == .failed else {
            throw AstraError.validation("Wait for this preview to finish before deleting it.")
        }

        if let resultPath = generation.resultImagePath {
            let userID: String
            do {
                let session = try await supabase.auth.session
                userID = session.user.id.uuidString.lowercased()
            } catch {
                throw AstraError.auth("Sign in again to delete this preview.")
            }

            let pathParts = resultPath.split(separator: "/").map(String.init)
            guard generation.userID.uuidString.lowercased() == userID,
                  pathParts.count == 5,
                  pathParts[0] == "users",
                  pathParts[1] == userID,
                  pathParts[2] == "studio",
                  pathParts[3] == id.uuidString.lowercased(),
                  !pathParts[4].isEmpty,
                  pathParts[4] != ".",
                  pathParts[4] != ".." else {
                throw AstraError.validation("That preview image doesn't belong to this account.")
            }

            do {
                _ = try await supabase.storage.from("user-content").remove(paths: [resultPath])
            } catch {
                throw AstraError.network("Couldn't remove the preview image. The preview is still saved; please try again.")
            }
        }

        do {
            try await supabase.from("studio_generations").delete().eq("id", value: id).execute()
        } catch {
            throw AstraError.network("The image was removed, but its preview history couldn't be cleared. Please try again.")
        }
    }
}

private struct StudioGenerateBody: Encodable, Sendable {
    let sourceGenerationID: UUID?
    let mode: String?
    let context: String?
    let instructions: String?
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
        sourceGenerationID = request.sourceGenerationID
        mode = request.inspirationMode
        context = request.inspirationContext
        instructions = request.inspirationInstructions
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
        case sourceGenerationID = "source_generation_id"
        case mode, context, instructions
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
