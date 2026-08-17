//
//  AnalyticsEventQueue.swift
//  AstraStyle
//
//  Durable, capped FIFO buffer for events waiting to reach
//  `analytics_events` (spec §18, `supabase/migrations/
//  20260816120000_analytics_events.sql`). Same SHAPE as `OfflineMutationQueue`
//  / `PendingScanQueue` (Domain/Services) — enqueue now, drain later in
//  batches, stop at the first failure to preserve ordering — but it is
//  deliberately NOT one of them. Two reasons:
//
//  1. `LiveAnalyticsClient` is constructed with zero arguments in
//     `AppContainer.live()` (`let analyticsClient = LiveAnalyticsClient()`),
//     built before the offline queue / shared `ModelContainer` even exist.
//     It cannot receive an injected `OfflineMutationQueue` without changing
//     that call site.
//  2. `OfflineMutation.Entity` is a closed enum with no `.analyticsEvent`
//     case. Widening it would mean every repository that pattern-matches
//     `OfflineMutation.entity` (`LiveClosetRepository`,
//     `LiveOutfitRepository`) has to grow a new `throw
//     OfflineMutationNotHandled()` branch for a payload that shares none of
//     that queue's actual purpose — CRUD replay with conflict resolution.
//     Analytics events never conflict; they are pure inserts with no
//     business meaning if dropped.
//
//  A second, purpose-built "append-only, best-effort, batched" queue is a
//  smaller and more honest surface than reusing one designed for CRUD
//  replay.
//
//  WHY A HARD CAP (`maxQueueLength`), UNLIKE THE OTHER TWO QUEUES.
//  `OfflineMutationQueue` / `PendingScanQueue` hold user edits and camera
//  captures — losing one is losing real work, so neither caps its size.
//  Analytics events are the opposite: spec's own framing for this ticket
//  ("a dropped event is strictly better than a slowed app") makes an
//  unbounded queue the wrong trade for a phone that's offline for days —
//  it would grow forever and then burst-upload a stale backlog nobody
//  asked for. Dropping the OLDEST events on overflow keeps the file small
//  and keeps whatever is most likely to still be relevant.
//

import Foundation

/// One event waiting to be written to `analytics_events`. Matches that
/// table's wire shape exactly via `CodingKeys` (see
/// `SupabaseAnalyticsEventSender`) — the same value is both what gets
/// persisted to disk between launches and what gets POSTed to Postgrest,
/// so there is exactly one shape to keep in sync with the migration.
public struct QueuedAnalyticsEvent: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let userID: UUID
    public let eventName: String
    public let properties: [String: AstraJSONValue]
    public let occurredAt: Date

    public init(id: UUID = UUID(), userID: UUID, event: AnalyticsEvent, occurredAt: Date = .now) {
        self.id = id
        self.userID = userID
        self.eventName = event.name
        self.properties = event.properties
        self.occurredAt = occurredAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case eventName = "event_name"
        case properties
        case occurredAt = "occurred_at"
    }
}

actor AnalyticsEventQueue {
    private var events: [QueuedAnalyticsEvent]
    private var identifiedUserID: UUID?
    private var isFlushing = false
    private let maxQueueLength: Int
    private let batchSize: Int
    private let store: AnalyticsEventDiskStore?

    init(maxQueueLength: Int = 500, batchSize: Int = 20, store: AnalyticsEventDiskStore? = .live) {
        self.maxQueueLength = maxQueueLength
        self.batchSize = batchSize
        self.store = store
        self.events = store?.load() ?? []
    }

    // MARK: - Identity (mirrors `AnalyticsClient.identify(userID:)` / `reset()`)

    func setIdentity(_ userID: UUID?) {
        identifiedUserID = userID
    }

    func currentIdentity() -> UUID? {
        identifiedUserID
    }

    // MARK: - Queueing

    func enqueue(_ event: QueuedAnalyticsEvent) {
        events.append(event)
        if events.count > maxQueueLength {
            events.removeFirst(events.count - maxQueueLength)
        }
        store?.save(events)
    }

    /// Attempts to send everything currently queued, in `batchSize`
    /// batches, oldest first. Stops at the first batch `send` fails to
    /// deliver — the same ordering guarantee `OfflineMutationQueue.drain`
    /// makes — so a batch is never retried out of order and a transient
    /// failure never silently skips ahead to newer events.
    ///
    /// `isFlushing` is a reentrancy guard, not a lock: `LiveAnalyticsClient`
    /// calls this both after every `log()` and from a periodic background
    /// timer, and an actor's own suspension points (the `await send(batch)`
    /// below) are exactly where two overlapping calls could otherwise both
    /// start sending the same head-of-queue batch.
    func drain(send: @Sendable ([QueuedAnalyticsEvent]) async throws -> Void) async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        while !events.isEmpty {
            let batch = Array(events.prefix(batchSize))
            do {
                try await send(batch)
                events.removeFirst(batch.count)
                store?.save(events)
            } catch {
                return
            }
        }
    }

    /// Test seam only — production code never needs to inspect the
    /// queue's contents, only enqueue into and drain it.
    func snapshot() -> [QueuedAnalyticsEvent] {
        events
    }
}
