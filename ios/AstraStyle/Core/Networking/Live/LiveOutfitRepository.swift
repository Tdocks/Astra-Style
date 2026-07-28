//
//  LiveOutfitRepository.swift
//  AstraStyle
//
//  `outfits` / `outfit_items` / `outfit_wears` / `daily_briefs` reads and
//  simple writes go through Postgrest; generation, ranking, brief
//  generation, and packing are orchestration calls that require the
//  Wardrobe Graph + weather/schedule context server-side (spec §14).
//

import Foundation
import Supabase

public final class LiveOutfitRepository: OutfitRepository, @unchecked Sendable {
    private let apiClient: AstraAPIClient
    private let supabase: SupabaseClient
    private let offlineQueue: OfflineMutationQueue

    public init(
        apiClient: AstraAPIClient,
        offlineQueue: OfflineMutationQueue,
        supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current)
    ) {
        self.apiClient = apiClient
        self.offlineQueue = offlineQueue
        self.supabase = supabase
    }

    public func fetchOutfits() async throws -> [Outfit] {
        do {
            return try await supabase.from("outfits").select().order("created_at", ascending: false).execute().value
        } catch {
            throw AstraError.network("Couldn't load your outfits.")
        }
    }

    public func fetchOutfit(id: UUID) async throws -> Outfit {
        do {
            return try await supabase.from("outfits").select().eq("id", value: id).single().execute().value
        } catch {
            throw AstraError.server("Couldn't load that outfit.")
        }
    }

    public func fetchOutfits(ids: [UUID]) async throws -> [Outfit] {
        guard !ids.isEmpty else { return [] }
        do {
            return try await supabase.from("outfits")
                .select()
                .in("id", values: ids)
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't load those outfits.")
        }
    }

    public func fetchOutfitItems(outfitID: UUID) async throws -> [OutfitItem] {
        do {
            return try await supabase.from("outfit_items")
                .select()
                .eq("outfit_id", value: outfitID)
                .order("sort_order", ascending: true)
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't load that outfit's items.")
        }
    }

    public func generateOutfits(_ request: OutfitGenerationRequest) async throws -> [OutfitRecommendation] {
        try await apiClient.send(.generateOutfits, body: GenerateOutfitsBody(request), as: [OutfitRecommendation].self)
    }

    public func rankOutfits(candidateOutfitIDs: [UUID], lockedClosetItemIDs: [UUID]) async throws -> [OutfitRecommendation] {
        struct Body: Encodable, Sendable {
            let candidateOutfitIDs: [UUID]
            let lockedClosetItemIDs: [UUID]
            enum CodingKeys: String, CodingKey {
                case candidateOutfitIDs = "candidate_outfit_ids"
                case lockedClosetItemIDs = "locked_closet_item_ids"
            }
        }
        return try await apiClient.send(
            .rankOutfits,
            body: Body(candidateOutfitIDs: candidateOutfitIDs, lockedClosetItemIDs: lockedClosetItemIDs),
            as: [OutfitRecommendation].self
        )
    }

    /// Persists an `outfits` row **and** its `outfit_items` rows for every
    /// resolvable item in `recommendation.itemIDs`.
    ///
    /// `POST /outfits/generate` (the Edge Function) returns a transient
    /// recommendation — it does not write to the database itself, so
    /// `recommendation.id` is not yet a real `outfits.id` anywhere. That
    /// matters beyond bookkeeping: `outfit_wears.outfit_id` is `NOT NULL
    /// REFERENCES outfits(id)` with no `ON DELETE SET NULL`
    /// (`supabase/migrations/20260728100400_outfits.sql`), so
    /// `recordWear(outfitID:...)` will fail a foreign-key check against any
    /// id that was never actually inserted here — and
    /// `bump_closet_item_wear_stats()` (the trigger that increments
    /// `closet_items.wear_count` on wear) joins through `outfit_items`, so
    /// without those rows the wear-count bump is silently a no-op even if
    /// the FK happened to pass. Both `outfits` and `outfit_items` inserts
    /// are therefore required, not optional, for a generated recommendation
    /// to ever be meaningfully "worn". `closetItems` is the caller's
    /// already-loaded closet (`SliceViewModel` has this in memory already)
    /// — used only to resolve each item's `category` into
    /// `outfit_items.role`, since the recommendation itself carries no role
    /// information, just a flat `item_ids` array.
    public func saveOutfit(from recommendation: OutfitRecommendation, name: String?, closetItems: [ClosetItem]) async throws -> Outfit {
        do {
            let session = try await supabase.auth.session
            let outfit = Outfit(
                id: recommendation.id,
                userID: session.user.id,
                name: name ?? recommendation.name,
                description: recommendation.reason,
                compatibilityScore: recommendation.compatibilityScore,
                source: .kyraGenerated
            )
            let saved: Outfit = try await supabase.from("outfits").insert(outfit).select().single().execute().value

            let itemsByID = Dictionary(uniqueKeysWithValues: closetItems.map { ($0.id, $0) })
            let outfitItems: [OutfitItem] = recommendation.itemIDs.enumerated().compactMap { index, closetItemID in
                // `outfit_items.role` reuses the `clothing_category` Postgres
                // enum verbatim (see 20260728100400_outfits.sql's column
                // comment), and `OutfitItemRole`'s raw values are a superset
                // of `ClothingCategory`'s — every real category maps.
                guard
                    let category = itemsByID[closetItemID]?.category,
                    let role = OutfitItemRole(rawValue: category.rawValue)
                else { return nil }
                return OutfitItem(outfitID: saved.id, closetItemID: closetItemID, role: role, sortOrder: index)
            }
            if !outfitItems.isEmpty {
                try await supabase.from("outfit_items").insert(outfitItems).execute()
            }

            return saved
        } catch {
            throw AstraError.server("Couldn't save that outfit.")
        }
    }

    public func updateOutfit(_ outfit: Outfit) async throws -> Outfit {
        do {
            return try await supabase.from("outfits")
                .update(outfit)
                .eq("id", value: outfit.id)
                .select()
                .single()
                .execute()
                .value
        } catch {
            let payload = try JSONEncoder.astraDefault.encode(outfit)
            await offlineQueue.enqueue(OfflineMutation(entity: .outfit, operation: .update, payloadData: payload))
            return outfit
        }
    }

    public func deleteOutfit(id: UUID) async throws {
        do {
            try await supabase.from("outfits").delete().eq("id", value: id).execute()
        } catch {
            throw AstraError.network("Couldn't delete that outfit while offline.")
        }
    }

    @discardableResult
    public func recordWear(outfitID: UUID, wornAt: Date, occasion: String?, rating: Int?, feedback: String?) async throws -> OutfitWear {
        do {
            let session = try await supabase.auth.session
            let wear = OutfitWear(
                id: UUID(),
                outfitID: outfitID,
                userID: session.user.id,
                wornAt: wornAt,
                occasion: occasion,
                rating: rating,
                feedback: feedback
            )
            return try await supabase.from("outfit_wears").insert(wear).select().single().execute().value
        } catch {
            let session = try? await supabase.auth.session
            let wear = OutfitWear(
                id: UUID(),
                outfitID: outfitID,
                userID: session?.user.id ?? UUID(),
                wornAt: wornAt,
                occasion: occasion,
                rating: rating,
                feedback: feedback
            )
            let payload = try JSONEncoder.astraDefault.encode(wear)
            await offlineQueue.enqueue(OfflineMutation(entity: .outfitWear, operation: .create, payloadData: payload))
            return wear
        }
    }

    public func fetchDailyBrief(for date: Date) async throws -> DailyBrief? {
        do {
            return try await supabase.from("daily_briefs")
                .select()
                .eq("brief_date", value: DateFormatter.astraDay.string(from: date))
                .single()
                .execute()
                .value
        } catch {
            return nil
        }
    }

    public func generateDailyBrief(for date: Date) async throws -> DailyBrief {
        struct Body: Encodable, Sendable {
            let date: String
        }
        return try await apiClient.send(
            .generateDailyBrief,
            body: Body(date: DateFormatter.astraDay.string(from: date)),
            as: DailyBrief.self
        )
    }

    public func generatePackingPlan(_ request: PackingRequest) async throws -> PackingPlan {
        struct Body: Encodable, Sendable {
            let destination: String
            let startDate: Date
            let endDate: Date
            let activities: [String]
            let dressCodes: [DressCode]
            let luggageConstraint: LuggageConstraint
            let hasLaundryAccess: Bool
            enum CodingKeys: String, CodingKey {
                case destination
                case startDate = "start_date"
                case endDate = "end_date"
                case activities
                case dressCodes = "dress_codes"
                case luggageConstraint = "luggage_constraint"
                case hasLaundryAccess = "has_laundry_access"
            }
        }
        return try await apiClient.send(
            .generatePacking,
            body: Body(
                destination: request.destination,
                startDate: request.startDate,
                endDate: request.endDate,
                activities: request.activities,
                dressCodes: request.dressCodes,
                luggageConstraint: request.luggageConstraint,
                hasLaundryAccess: request.hasLaundryAccess
            ),
            as: PackingPlan.self
        )
    }
}

/// `POST /outfits/generate` request body.
private struct GenerateOutfitsBody: Encodable, Sendable {
    let occasionID: UUID?
    let naturalLanguageRequest: String?
    let lockedClosetItemIDs: [UUID]
    let excludedClosetItemIDs: [UUID]
    let desiredCount: Int

    init(_ request: OutfitGenerationRequest) {
        occasionID = request.occasionID
        naturalLanguageRequest = request.naturalLanguageRequest
        lockedClosetItemIDs = request.lockedClosetItemIDs
        excludedClosetItemIDs = request.excludedClosetItemIDs
        desiredCount = request.desiredCount
    }

    enum CodingKeys: String, CodingKey {
        case occasionID = "occasion_id"
        case naturalLanguageRequest = "natural_language_request"
        case lockedClosetItemIDs = "locked_closet_item_ids"
        case excludedClosetItemIDs = "excluded_closet_item_ids"
        case desiredCount = "desired_count"
    }
}

extension DateFormatter {
    /// `YYYY-MM-DD`, matching the Postgres `date` column type used by
    /// `daily_briefs.brief_date` (spec §9).
    static let astraDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        return formatter
    }()
}
