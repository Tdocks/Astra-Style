//
//  ClosetWriting.swift
//  AstraStyle
//
//  The Postgrest writes `LiveClosetRepository` performs, behind a protocol.
//
//  This seam exists for one specific reason. Spec §7's offline behaviour —
//  "local edits and new scans queue for sync" — is implemented as an
//  `OfflineMutationQueue` that mutations are enqueued into on failure and
//  replayed from when a later call succeeds. The queue itself has always been
//  well tested (Tests/UnitTests/OfflineMutationQueueTests.swift). The WIRING
//  around it was not tested at all, and was in fact absent: nothing in the app
//  ever called `drain(apply:)`, so every queued mutation sat there forever
//  while `LiveClosetRepository`'s header comment claimed the opposite.
//
//  The reason that went unnoticed for so long is that the only way to reach
//  the wiring was through a live `SupabaseClient` pointed at a real project.
//  Splitting the three writes out means the enqueue-on-failure and
//  drain-on-success behaviour can be driven from a unit test with a stub
//  writer, which is what `Tests/UnitTests/OfflineDrainWiringTests.swift` does.
//

import Foundation
import Supabase

/// The closet writes that can be performed against the backend, and that a
/// queued offline mutation is replayed through.
protocol ClosetWriting: Sendable {
    func create(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem
    func update(_ item: ClosetItem) async throws -> ClosetItem
    func archive(id: UUID) async throws
}

/// The production conformance: plain Postgrest calls, no offline handling.
///
/// Deliberately dumb. Everything about queueing, ordering and replay lives in
/// `LiveClosetRepository`, so there is exactly one place that decides what
/// happens when a write fails — rather than that policy being split across a
/// repository and the thing it writes through.
struct SupabaseClosetWriter: ClosetWriting {
    let supabase: SupabaseClient

    func create(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        let created: ClosetItem = try await supabase.from("closet_items")
            .insert(item)
            .select()
            .single()
            .execute()
            .value
        if !images.isEmpty {
            try await supabase.from("closet_item_images").insert(images).execute()
        }
        return created
    }

    func update(_ item: ClosetItem) async throws -> ClosetItem {
        try await supabase.from("closet_items")
            .update(item)
            .eq("id", value: item.id)
            .select()
            .single()
            .execute()
            .value
    }

    func archive(id: UUID) async throws {
        try await supabase.from("closet_items")
            .update(["archived_at": Date.now])
            .eq("id", value: id)
            .execute()
    }
}
