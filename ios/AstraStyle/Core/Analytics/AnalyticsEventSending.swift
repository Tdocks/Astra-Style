//
//  AnalyticsEventSending.swift
//  AstraStyle
//
//  The one Postgrest call `LiveAnalyticsClient` performs, behind a
//  protocol — the same seam `OutfitWriting` / `ClosetWriting`
//  (Core/Networking/Live) exist for, and for the same reason: it lets
//  `AnalyticsEventQueue`'s batching / offline / never-throws behaviour be
//  driven from a unit test with a stub sender, instead of requiring a live
//  Supabase project the way exercising `LiveAnalyticsClient`'s convenience
//  initializer would.
//

import Foundation
import Supabase

protocol AnalyticsEventSending: Sendable {
    /// Sends one batch. Throwing leaves the batch — and everything queued
    /// behind it — in place for the next attempt; see
    /// `AnalyticsEventQueue.drain(send:)`.
    func send(_ events: [QueuedAnalyticsEvent]) async throws
}

/// Production conformance: a single bulk insert per batch. No `.select()`
/// echo-back — unlike every other `Supabase*Writer` in this codebase,
/// nothing reads the inserted rows back (there is no cache, no UI state
/// derived from an analytics event), so asking Postgrest to return them
/// would be pure overhead on a call that already has to stay off the
/// critical path (this ticket's "never delay a screen" requirement).
struct SupabaseAnalyticsEventSender: AnalyticsEventSending {
    let supabase: SupabaseClient

    func send(_ events: [QueuedAnalyticsEvent]) async throws {
        guard !events.isEmpty else { return }
        try await supabase.from("analytics_events").insert(events).execute()
    }
}
