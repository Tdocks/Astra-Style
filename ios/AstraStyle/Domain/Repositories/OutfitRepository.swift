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

    /// Writes one `style_feedback` row (spec §9 signals; P4-OUTFIT-14).
    ///
    /// Distinct from `recordWear`: a "wore it" is a real event against a
    /// real `outfits` row and is what the `bump_closet_item_wear_stats()`
    /// trigger keys off, while a like/dislike/skip/etc. is a durable
    /// opinion signal that feeds the §10 compatibility formula's
    /// "historical co-wear/feedback" term and can target an outfit, a
    /// closet item, an outfit item, or a product candidate —
    /// `targetType`/`targetID` are polymorphic per the `style_feedback`
    /// migration's own comment, and this repository does not validate
    /// `targetID` against the table `targetType` implies; the caller is
    /// responsible for passing a real id (the same trade-off the
    /// migration itself documents at the database layer).
    @discardableResult
    func recordFeedback(
        targetType: StyleFeedbackTargetType,
        targetID: UUID,
        signal: StyleFeedbackSignal,
        reasonTags: [String],
        freeText: String?
    ) async throws -> StyleFeedback

    /// Fetches the already-generated brief for a given date, if one exists.
    func fetchDailyBrief(for date: Date) async throws -> DailyBrief?

    /// Calls `POST /daily-brief/generate` (spec §14) — used when no brief
    /// exists yet for today, or the user asks Kyra to regenerate it.
    ///
    /// `regenerate` has to be stated because the endpoint is idempotent per
    /// `brief_date` (P4-HOME-02): without it, the second call of the day
    /// returns the brief already stored, and §6.11's regenerate control
    /// would hand the user back the same outfits he just asked to replace —
    /// a button that appears to work and does nothing. Defaulted to `false`
    /// so the ordinary "no brief yet" path cannot rebuild by accident: a
    /// client retrying after a dropped connection must not replace outfits
    /// a user is looking at.
    ///
    /// `weather` (P4-HOME-05) is the client's own `WeatherService` reading,
    /// passed up rather than looked up server-side because there is no
    /// server-side weather provider (`daily-brief/README.md`'s "What it
    /// deliberately does not produce"). `nil` when weather permission was
    /// never granted or the lookup failed — the server persists exactly
    /// what it is given and never invents a forecast to fill the column.
    func generateDailyBrief(for date: Date, regenerate: Bool, weather: WeatherSnapshot?) async throws -> DailyBrief

    /// Calls `POST /packing/generate` (spec §6.24, §14).
    func generatePackingPlan(_ request: PackingRequest) async throws -> PackingPlan

    /// Other men's public worn looks for Discover. Home must never call this.
    func fetchPublicWornLooks() async throws -> [Outfit]

    /// Stub report of a public lookbook. Idempotent per reporter.
    func reportLookbook(outfitID: UUID) async throws
}

public extension OutfitRepository {
    /// The overwhelmingly common call — "today's brief, whatever already
    /// exists" — kept as a default so every caller that does not mean
    /// "rebuild" does not have to say so.
    func generateDailyBrief(for date: Date) async throws -> DailyBrief {
        try await generateDailyBrief(for: date, regenerate: false, weather: nil)
    }

    /// `recordFeedback` without reason tags or free text — the common
    /// "skip"/"dislike" tap, which carries only a signal. A default
    /// parameter value on the protocol requirement itself would not be
    /// honored when called through the `OutfitRepository` existential
    /// (every call site in this app holds one), so this overload exists
    /// for the same reason `generateDailyBrief(for:)` above does.
    @discardableResult
    func recordFeedback(targetType: StyleFeedbackTargetType, targetID: UUID, signal: StyleFeedbackSignal) async throws -> StyleFeedback {
        try await recordFeedback(targetType: targetType, targetID: targetID, signal: signal, reasonTags: [], freeText: nil)
    }

    func fetchPublicWornLooks() async throws -> [Outfit] { [] }

    func reportLookbook(outfitID: UUID) async throws {}
}
