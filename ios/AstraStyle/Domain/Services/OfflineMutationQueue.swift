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
    }

    public enum Operation: String, Codable, Sendable {
        case create
        case update
        case delete
    }
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
    func drain(apply: @Sendable (OfflineMutation) async throws -> Void) async

    /// Removes a single mutation, e.g. after it fails validation
    /// permanently and the user has been asked to resolve the conflict.
    func remove(id: UUID) async

    func clear() async
}
