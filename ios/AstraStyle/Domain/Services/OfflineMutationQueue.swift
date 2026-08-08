//
//  OfflineMutationQueue.swift
//  AstraStyle
//
//  Protocol surface for spec §7 "Offline behavior": local edits and new
//  scans queue for sync when there's no connectivity; cached closet and
//  outfits remain viewable; generative features still require network (so
//  this queue only ever carries CRUD-shaped mutations, never a "generate
//  an outfit offline" request).
//
//  `SwiftDataOfflineMutationQueue` (Core/Persistence) is the production
//  conformance; `InMemoryOfflineMutationQueue` (Core/Mocks) backs previews.
//

import Foundation

/// A single pending write, queued in the order it should be replayed
/// (spec §22 "Unit tests: Offline queue" — ordering is explicitly a
/// tested contract, so this type stays a plain, comparable value).
public struct OfflineMutation: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let entity: Entity
    public let operation: Operation
    /// JSON-encoded payload of the domain model being written (e.g. an
    /// encoded `ClosetItem`). Kept as raw `Data` here so the queue itself
    /// has no compile-time dependency on every possible mutated type.
    public let payloadData: Data
    public let enqueuedAt: Date
    public var attemptCount: Int

    public init(
        id: UUID = UUID(),
        entity: Entity,
        operation: Operation,
        payloadData: Data,
        enqueuedAt: Date = .now,
        attemptCount: Int = 0
    ) {
        self.id = id
        self.entity = entity
        self.operation = operation
        self.payloadData = payloadData
        self.enqueuedAt = enqueuedAt
        self.attemptCount = attemptCount
    }

    public enum Entity: String, Codable, Sendable {
        case closetItem
        case outfit
        case outfitWear
        case occasion
        /// A `style_feedback` row (P4-OUTFIT-14: like/dislike/skip/etc. on
        /// an outfit, closet item, or product candidate). Replayed by
        /// `LiveOutfitRepository+Offline.swift` alongside `.outfitWear` —
        /// same insert-with-a-client-minted-id shape, same reasoning for
        /// why no conflict-resolution pass is needed.
        case styleFeedback
    }

    public enum Operation: String, Codable, Sendable {
        case create
        case update
        case delete
    }
}

/// Thrown by a `drain(apply:)` handler that does not own the mutation it was
/// handed.
///
/// One queue holds mutations for four entity types (`LiveClosetRepository`
/// enqueues `.closetItem`; `LiveOutfitRepository` enqueues `.outfit` and
/// `.outfitWear`), but each repository can only replay its own. Without this
/// signal a closet drain meeting a queued outfit mutation has two bad options:
/// treat it as a failure — which stops the drain forever and burns a retry
/// count on something that will never succeed — or apply/remove it, which
/// silently destroys a write whose owner will never know it vanished.
///
/// Skipping is the third option, and the correct one: the mutation stays
/// queued, unmodified and uncounted, for whoever does own it. Ordering across
/// entity types was never something this queue could promise once two owners
/// shared it; ordering *within* an entity is unaffected, because skipping
/// never reorders anything.
public struct OfflineMutationNotHandled: Error, Sendable {
    public init() {}
}

public protocol OfflineMutationQueue: Sendable {
    /// Adds a mutation to the end of the queue. Mutations are always
    /// replayed in FIFO order, so an `update` enqueued after a `create` for
    /// the same entity is guaranteed to apply after it.
    func enqueue(_ mutation: OfflineMutation) async

    /// All pending mutations, oldest first.
    func pendingMutations() async -> [OfflineMutation]

    /// Attempts to replay every pending mutation via `apply`, in order,
    /// stopping at the first failure (to preserve ordering) and leaving
    /// the remainder queued. Successfully-applied mutations are removed.
    ///
    /// A handler that throws `OfflineMutationNotHandled` is saying "not
    /// mine": that mutation is skipped — left in place, attempt count
    /// untouched — and the drain continues with the next one.
    ///
    /// The mutation that failed stays at the head of the queue with its
    /// `attemptCount` incremented. That counter is the only evidence a
    /// reader has that a queue which never shrinks is stuck rather than
    /// simply idle — a conformance that leaves it at zero makes a
    /// permanently-failing mutation indistinguishable from one that has
    /// never been tried.
    func drain(apply: @Sendable (OfflineMutation) async throws -> Void) async

    /// Removes a single mutation, e.g. after it fails validation
    /// permanently and the user has been asked to resolve the conflict.
    func remove(id: UUID) async

    func clear() async
}
