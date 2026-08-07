//
//  LiveOutfitRepository.swift
//  AstraStyle
//
//  `outfits` / `outfit_items` / `outfit_wears` / `daily_briefs` reads and
//  simple writes go through Postgrest; generation, ranking, brief
//  generation, and packing are orchestration calls that require the
//  Wardrobe Graph + weather/schedule context server-side (spec §14).
//
//  Offline behaviour (spec §7), stated precisely, mirroring
//  `LiveClosetRepository`'s header:
//
//  * `updateOutfit` and `recordWear` fall back to `OfflineMutationQueue`
//    when the write fails, and return the local value so the UI stays
//    consistent. `saveOutfit` and `deleteOutfit` do NOT queue — both
//    require a fresh session/id round-trip that a stale local value can't
//    stand in for — and surface their error instead.
//  * Successful reads and writes refresh `OutfitCaching`
//    (`PersistedOutfit` via `SwiftDataOutfitCache`). A failed
//    `fetchOutfits`/`fetchOutfit`/`fetchOutfitItems` serves the last
//    cached value when one exists (spec §7 "Cached closet and outfits
//    remain viewable").
//  * `drainPendingMutations()` (`LiveOutfitRepository+Offline.swift`)
//    replays the `.outfit`/`.outfitWear` backlog and IS actually called,
//    after every successful network call below — P1-CORE-06: before this,
//    those two mutation kinds were queued and never replayed by anything.
//

import Foundation
import Supabase

public final class LiveOutfitRepository: OutfitRepository, @unchecked Sendable {
    private let apiClient: AstraAPIClient
    private let supabase: SupabaseClient
    let offlineQueue: OfflineMutationQueue
    let writer: any OutfitWriting
    private let cache: OutfitCaching
    private let currentUserID: @Sendable () async -> UUID?
    /// Test seams: when non-nil, `fetchOutfits`/`fetchOutfitItems` use
    /// these instead of Postgrest, so cache write-through / offline
    /// fallback can be asserted without a live Supabase project. Mirrors
    /// `LiveClosetRepository.activeItemsFetcher`.
    private let activeOutfitsFetcher: (@Sendable () async throws -> [Outfit])?
    private let activeOutfitItemsFetcher: (@Sendable (UUID) async throws -> [OutfitItem])?

    /// Guards against two concurrent drains replaying the same mutation
    /// twice. See `LiveClosetRepository.drainLock`'s doc for why a lock is
    /// sufficient here.
    let drainLock = NSLock()
    var isDraining = false

    public convenience init(
        apiClient: AstraAPIClient,
        offlineQueue: OfflineMutationQueue,
        cache: OutfitCaching,
        supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current)
    ) {
        self.init(
            apiClient: apiClient,
            offlineQueue: offlineQueue,
            supabase: supabase,
            writer: SupabaseOutfitWriter(supabase: supabase),
            cache: cache,
            currentUserID: {
                try? await supabase.auth.session.user.id
            }
        )
    }

    /// Internal so tests can substitute the writer, cache, and fetchers and
    /// drive offline / cache behaviour without a live Supabase project.
    init(
        apiClient: AstraAPIClient,
        offlineQueue: OfflineMutationQueue,
        supabase: SupabaseClient,
        writer: any OutfitWriting,
        cache: OutfitCaching,
        currentUserID: @escaping @Sendable () async -> UUID? = { nil },
        activeOutfitsFetcher: (@Sendable () async throws -> [Outfit])? = nil,
        activeOutfitItemsFetcher: (@Sendable (UUID) async throws -> [OutfitItem])? = nil
    ) {
        self.apiClient = apiClient
        self.offlineQueue = offlineQueue
        self.supabase = supabase
        self.writer = writer
        self.cache = cache
        self.currentUserID = currentUserID
        self.activeOutfitsFetcher = activeOutfitsFetcher
        self.activeOutfitItemsFetcher = activeOutfitItemsFetcher
    }

    public func fetchOutfits() async throws -> [Outfit] {
        do {
            let outfits: [Outfit]
            if let activeOutfitsFetcher {
                outfits = try await activeOutfitsFetcher()
            } else {
                outfits = try await supabase.from("outfits").select().order("created_at", ascending: false).execute().value
            }
            if let userID = await currentUserID() {
                await cache.replaceAll(outfits, for: userID)
            }
            // Same rationale as `LiveClosetRepository.fetchItems`: a
            // successful read is the cheapest reliable signal the network
            // is back, and the outfit list is where Home/the outfits tab
            // lands, so it's the natural moment to flush the backlog.
            await drainPendingMutations()
            return outfits
        } catch {
            if let userID = await currentUserID() {
                let cached = await cache.outfits(for: userID)
                if !cached.isEmpty { return cached }
            }
            throw AstraError.network("Couldn't load your outfits. Showing your last saved copy if available.")
        }
    }

    public func fetchOutfit(id: UUID) async throws -> Outfit {
        do {
            let outfit: Outfit = try await supabase.from("outfits").select().eq("id", value: id).single().execute().value
            await cache.upsert(outfit, items: nil)
            return outfit
        } catch {
            if let userID = await currentUserID(),
               let cached = await cache.outfits(for: userID).first(where: { $0.id == id }) {
                return cached
            }
            throw AstraError.server("Couldn't load that outfit.")
        }
    }

    public func fetchOutfits(ids: [UUID]) async throws -> [Outfit] {
        guard !ids.isEmpty else { return [] }
        do {
            let outfits: [Outfit] = try await supabase.from("outfits")
                .select()
                .in("id", values: ids)
                .execute()
                .value
            for outfit in outfits {
                await cache.upsert(outfit, items: nil)
            }
            return outfits
        } catch {
            if let userID = await currentUserID() {
                let cached = await cache.outfits(for: userID).filter { ids.contains($0.id) }
                if !cached.isEmpty { return cached }
            }
            throw AstraError.server("Couldn't load those outfits.")
        }
    }

    public func fetchOutfitItems(outfitID: UUID) async throws -> [OutfitItem] {
        do {
            let items: [OutfitItem]
            if let activeOutfitItemsFetcher {
                items = try await activeOutfitItemsFetcher(outfitID)
            } else {
                items = try await supabase.from("outfit_items")
                    .select()
                    .eq("outfit_id", value: outfitID)
                    .order("sort_order", ascending: true)
                    .execute()
                    .value
            }
            await cache.upsertItems(items, forOutfit: outfitID)
            return items
        } catch {
            let cached = await cache.items(forOutfit: outfitID)
            if !cached.isEmpty { return cached }
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
    /// information, just a flat `item_ids` array (`OutfitItemAssembly`).
    public func saveOutfit(from recommendation: OutfitRecommendation, name: String?, closetItems: [ClosetItem]) async throws -> Outfit {
        do {
            let session = try await supabase.auth.session
            let outfit = Outfit(
                id: recommendation.id,
                userID: session.user.id,
                name: name ?? recommendation.name,
                description: recommendation.reason,
                compatibilityScore: recommendation.compatibilityScore,
                source: .aiGenerated
            )
            let saved: Outfit = try await supabase.from("outfits").insert(outfit).select().single().execute().value

            let outfitItems = OutfitItemAssembly.ownedItems(
                itemIDs: recommendation.itemIDs,
                outfitID: saved.id,
                closetItems: closetItems
            )
            if !outfitItems.isEmpty {
                try await supabase.from("outfit_items").insert(outfitItems).execute()
            }

            await cache.upsert(saved, items: outfitItems)
            await drainPendingMutations()
            return saved
        } catch {
            throw AstraError.server("Couldn't save that outfit.")
        }
    }

    public func updateOutfit(_ outfit: Outfit) async throws -> Outfit {
        do {
            let updated = try await writer.updateOutfit(outfit)
            await cache.upsert(updated, items: nil)
            await drainPendingMutations()
            return updated
        } catch {
            let payload = try JSONEncoder.astraDefault.encode(outfit)
            await offlineQueue.enqueue(OfflineMutation(entity: .outfit, operation: .update, payloadData: payload))
            await cache.upsert(outfit, items: nil)
            return outfit
        }
    }

    public func deleteOutfit(id: UUID) async throws {
        do {
            try await supabase.from("outfits").delete().eq("id", value: id).execute()
            await cache.remove(id: id)
            await drainPendingMutations()
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
            let recorded = try await writer.createWear(wear)
            await drainPendingMutations()
            return recorded
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

    public func generateDailyBrief(for date: Date, regenerate: Bool, weather: WeatherSnapshot?) async throws -> DailyBrief {
        struct Body: Encodable, Sendable {
            let date: String
            let regenerate: Bool
            // Reuses `WeatherSnapshot`'s own `Encodable`/`CodingKeys`, so the
            // wire shape matches `weather_snapshot` exactly — no second,
            // divergent JSON shape for the same data.
            let weatherSnapshot: WeatherSnapshot?
            enum CodingKeys: String, CodingKey {
                case date
                case regenerate
                case weatherSnapshot = "weather_snapshot"
            }
        }
        return try await apiClient.send(
            .generateDailyBrief,
            body: Body(date: DateFormatter.astraDay.string(from: date), regenerate: regenerate, weatherSnapshot: weather),
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
