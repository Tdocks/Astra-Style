//
//  OutfitWriting.swift
//  AstraStyle
//
//  The Postgrest writes `LiveOutfitRepository` performs for `.outfit` /
//  `.outfitWear` offline mutations, behind a protocol — the same seam
//  `ClosetWriting` exists for, and for the same reason (see that file's
//  header): `updateOutfit`/`recordWear` enqueue-on-failure was already
//  correct, but nothing ever called `drain(apply:)` for these two entity
//  types (P1-CORE-06), and the only way to exercise that wiring was
//  through a live Supabase project. Splitting these two writes out lets
//  `Tests/UnitTests/OutfitOfflineDrainWiringTests.swift` drive it with a
//  stub.
//

import Foundation
import Supabase

/// The outfit writes that a queued `.outfit`/`.outfitWear` mutation is
/// replayed through. Deliberately just these two — `saveOutfit` and
/// `deleteOutfit` never queue (see `LiveOutfitRepository`), so there is
/// nothing else to replay.
protocol OutfitWriting: Sendable {
    func updateOutfit(_ outfit: Outfit) async throws -> Outfit
    func createWear(_ wear: OutfitWear) async throws -> OutfitWear
    /// P4-OUTFIT-14: the `style_feedback` half of wear feedback capture
    /// (like/dislike/skip/etc., distinct from the `outfit_wears` row
    /// `createWear` inserts). Added alongside the other two rather than
    /// given its own `FeedbackWriting` protocol — a queued
    /// `.styleFeedback` mutation is replayed by the same drain loop, for
    /// the same reason `OutfitWriting`'s header gives for `.outfit` /
    /// `.outfitWear` living together.
    func createFeedback(_ feedback: StyleFeedback) async throws -> StyleFeedback
}

/// The production conformance: plain Postgrest calls, no offline handling
/// — everything about queueing, ordering and replay stays in
/// `LiveOutfitRepository`, mirroring `SupabaseClosetWriter`.
struct SupabaseOutfitWriter: OutfitWriting {
    let supabase: SupabaseClient

    func updateOutfit(_ outfit: Outfit) async throws -> Outfit {
        try await supabase.from("outfits")
            .update(outfit)
            .eq("id", value: outfit.id)
            .select()
            .single()
            .execute()
            .value
    }

    func createWear(_ wear: OutfitWear) async throws -> OutfitWear {
        // A response can be lost after the live write or a previous replay
        // committed. Ignore the existing ID rather than firing wear triggers twice.
        try await supabase.from("outfit_wears")
            .upsert(wear, onConflict: "id", ignoreDuplicates: true)
            .execute()
        let stored: OutfitWear = try await supabase.from("outfit_wears")
            .select().eq("id", value: wear.id).single().execute().value
        guard stored.userID == wear.userID, stored.outfitID == wear.outfitID,
              abs(stored.wornAt.timeIntervalSince(wear.wornAt)) < 0.001,
              stored.occasion == wear.occasion, stored.rating == wear.rating,
              stored.feedback == wear.feedback else {
            throw AstraError.validation("That wear record could not be safely recovered.")
        }
        return stored
    }

    func createFeedback(_ feedback: StyleFeedback) async throws -> StyleFeedback {
        try await supabase.from("style_feedback")
            .insert(feedback)
            .select()
            .single()
            .execute()
            .value
    }
}
