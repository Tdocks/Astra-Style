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
        struct Result: Decodable, Sendable { let id: UUID; let status: String }
        _ = try await apiClient.send(.deleteStudioGeneration(id: id), as: Result.self)
    }

    public func fetchPendingImageDeletionCount() async throws -> Int {
        let owner = try await collectionUserID()
        do {
            let response = try await supabase.from("studio_retention_jobs")
                .select("id", head: true, count: .exact).eq("user_id", value: owner)
                .neq("status", value: "complete").execute()
            guard let count = response.count else { throw AstraError.server("Couldn't check image removal.") }
            return count
        } catch { throw AstraError.network("Couldn't check image removal. Try again.") }
    }

    public func fetchLookbooks(offset: Int, limit: Int) async throws -> [StudioLookbook] {
        guard offset >= 0, (1...100).contains(limit) else { throw AstraError.validation("That collection page is invalid.") }
        let owner = try await collectionUserID()
        do {
            return try await supabase.from("studio_lookbooks").select().eq("user_id", value: owner)
                .order("created_at", ascending: false).order("id", ascending: false)
                .range(from: offset, to: offset + limit - 1).execute().value
        } catch { throw AstraError.network("Couldn't load your saved-look collections.") }
    }

    public func createLookbook(name: String) async throws -> StudioLookbook {
        struct Body: Encodable { let user_id: UUID; let name: String }
        let name = try StudioLookbook.validatedName(name)
        let owner = try await collectionUserID()
        do {
            return try await supabase.from("studio_lookbooks").insert(Body(user_id: owner, name: name))
                .select().single().execute().value
        } catch { throw AstraError.network("Couldn't create that collection. Try again.") }
    }

    public func renameLookbook(id: UUID, name: String) async throws {
        struct Body: Encodable { let name: String }
        let name = try StudioLookbook.validatedName(name)
        let owner = try await collectionUserID()
        do {
            let _: StudioLookbook = try await supabase.from("studio_lookbooks").update(Body(name: name))
                .eq("id", value: id).eq("user_id", value: owner).select().single().execute().value
        } catch { throw AstraError.network("Couldn't rename that collection. Try again.") }
    }

    public func deleteLookbook(id: UUID) async throws {
        let owner = try await collectionUserID()
        do {
            try await supabase.from("studio_lookbooks").delete().eq("id", value: id).eq("user_id", value: owner).execute()
        } catch { throw AstraError.network("Couldn't remove that collection. Try again.") }
    }

    public func fetchSavedLookbookIDs(generationID: UUID) async throws -> Set<UUID> {
        struct Entry: Decodable { let lookbook_id: UUID }
        let owner = try await collectionUserID()
        var ids: Set<UUID> = []
        var offset = 0
        do {
            while true {
                try Task.checkCancellation()
                let rows: [Entry] = try await supabase.from("studio_lookbook_entries").select("lookbook_id")
                    .eq("user_id", value: owner).eq("generation_id", value: generationID)
                    .order("id").range(from: offset, to: offset + 499).execute().value
                ids.formUnion(rows.map(\.lookbook_id))
                if rows.count < 500 { return ids }
                offset += rows.count
            }
        } catch is CancellationError { throw CancellationError() }
        catch { throw AstraError.network("Couldn't load where this look is saved.") }
    }

    public func fetchLookbookGenerations(lookbookID: UUID, offset: Int, limit: Int) async throws -> [StudioGeneration] {
        struct Entry: Decodable { let generation: StudioGeneration }
        guard offset >= 0, (1...100).contains(limit) else { throw AstraError.validation("That collection page is invalid.") }
        let owner = try await collectionUserID()
        do {
            let rows: [Entry] = try await supabase.from("studio_lookbook_entries")
                .select("generation:studio_generations!studio_lookbook_entries_generation_owner_fk!inner(*)")
                .eq("user_id", value: owner).eq("lookbook_id", value: lookbookID)
                .order("created_at", ascending: false).order("id", ascending: false)
                .range(from: offset, to: offset + limit - 1).execute().value
            return rows.map(\.generation)
        } catch { throw AstraError.network("Couldn't load that saved-look collection.") }
    }

    public func saveGeneration(id: UUID, to lookbookID: UUID) async throws {
        struct Entry: Encodable { let user_id: UUID; let generation_id: UUID; let lookbook_id: UUID }
        let owner = try await collectionUserID()
        do {
            try await supabase.from("studio_lookbook_entries")
                .upsert(Entry(user_id: owner, generation_id: id, lookbook_id: lookbookID),
                        onConflict: "lookbook_id,generation_id", ignoreDuplicates: true).execute()
        } catch { throw AstraError.network("Couldn't save this look. Check that the estimate has finished and try again.") }
    }

    public func removeGeneration(id: UUID, from lookbookID: UUID) async throws {
        let owner = try await collectionUserID()
        do {
            try await supabase.from("studio_lookbook_entries").delete().eq("user_id", value: owner)
                .eq("generation_id", value: id).eq("lookbook_id", value: lookbookID).execute()
        } catch { throw AstraError.network("Couldn't remove this look from the collection. Try again.") }
    }

    private func collectionUserID() async throws -> UUID {
        do { return try await supabase.auth.session.user.id }
        catch { throw AstraError.auth("Sign in again to manage your saved looks.") }
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
