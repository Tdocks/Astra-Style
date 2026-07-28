//
//  OutfitRepository.swift
//  AstraStyle
//
//  Owns `outfits` / `outfit_items` / `outfit_wears` / `daily_briefs`
//  (spec §9), outfit generation/ranking (spec §14), and the packing
//  assistant (spec §6.24, §14 `packing/generate`) — packing is fundamentally
//  a multi-day outfit plan, so it lives here rather than as its own
//  repository.
//
//  This is what `HomeViewModel` (Features/Home) depends on for Kyra's
//  Daily Brief.
//

import Foundation

public protocol OutfitRepository: Sendable {
    func fetchOutfits() async throws -> [Outfit]
    func fetchOutfit(id: UUID) async throws -> Outfit
    func fetchOutfits(ids: [UUID]) async throws -> [Outfit]
    func fetchOutfitItems(outfitID: UUID) async throws -> [OutfitItem]

    /// Calls `POST /outfits/generate` (spec §5.4, §14).
    func generateOutfits(_ request: OutfitGenerationRequest) async throws -> [OutfitRecommendation]

    /// Calls `POST /outfits/rank` (spec §14) — used when the user has
    /// locked some items and wants the rest regenerated/re-ranked
    /// (spec §5.4 "User can lock items and regenerate the rest").
    func rankOutfits(candidateOutfitIDs: [UUID], lockedClosetItemIDs: [UUID]) async throws -> [OutfitRecommendation]

    /// Persists `recommendation` as a real `outfits` row plus one
    /// `outfit_items` row per resolvable entry in `recommendation.itemIDs`
    /// (`closetItems` supplies the category each item needs for
    /// `outfit_items.role` — the recommendation itself carries no role
    /// info). This is required, not optional, before an id from
    /// `generateOutfits` can be passed to `recordWear`: `outfit_wears
    /// .outfit_id` is a `NOT NULL` foreign key with no `ON DELETE SET
    /// NULL`, so recording a wear against an outfit that was never
    /// actually saved fails outright, and the `wear_count`-bumping trigger
    /// needs real `outfit_items` rows to have anything to join against.
    func saveOutfit(from recommendation: OutfitRecommendation, name: String?, closetItems: [ClosetItem]) async throws -> Outfit
    func updateOutfit(_ outfit: Outfit) async throws -> Outfit
    func deleteOutfit(id: UUID) async throws

    @discardableResult
    func recordWear(outfitID: UUID, wornAt: Date, occasion: String?, rating: Int?, feedback: String?) async throws -> OutfitWear

    /// Fetches the already-generated brief for a given date, if one exists.
    func fetchDailyBrief(for date: Date) async throws -> DailyBrief?

    /// Calls `POST /daily-brief/generate` (spec §14) — used when no brief
    /// exists yet for today, or the user asks Kyra to regenerate it.
    func generateDailyBrief(for date: Date) async throws -> DailyBrief

    /// Calls `POST /packing/generate` (spec §6.24, §14).
    func generatePackingPlan(_ request: PackingRequest) async throws -> PackingPlan
}
