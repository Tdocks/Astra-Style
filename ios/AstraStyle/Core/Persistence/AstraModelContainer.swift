//
//  AstraModelContainer.swift
//  AstraStyle
//
//  Central SwiftData schema/container factory (spec §8 "SwiftData for
//  local cache and offline-first entities"). Only the entities spec §7
//  requires to remain viewable offline are cached here: closet items,
//  outfits, and daily briefs — plus the offline mutation queue itself.
//  Everything else (Kyra threads, Style Studio history, product
//  evaluations) is treated as network-first and simply not cached.
//

import Foundation
import SwiftData

public enum AstraModelContainer {
    public static let schema = Schema([
        PersistedClosetItem.self,
        PersistedOutfit.self,
        PersistedDailyBrief.self,
        PersistedOfflineMutation.self,
        PersistedPendingScan.self
    ])

    /// The production, on-disk container.
    public static func live() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// An in-memory container for previews and tests — never touches disk,
    /// and is discarded when the process exits.
    public static func preview() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // An in-memory SwiftData container failing to initialize indicates
        // a schema bug that should fail loudly in every preview/test/CI
        // run rather than be silently swallowed — hence `fatalError`
        // instead of propagating an error nobody in a preview context
        // would see. We still avoid a bare `try!` per house style.
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            fatalError("Failed to create in-memory SwiftData container for previews — check AstraModelContainer.schema for a modeling error.")
        }
        return container
    }
}
