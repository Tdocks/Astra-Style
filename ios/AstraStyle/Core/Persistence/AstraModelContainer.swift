//
//  AstraModelContainer.swift
//  AstraStyle
//
//  Central SwiftData schema/container factory (spec §8 "SwiftData for
//  local cache and offline-first entities"). Only the entities spec §7
//  requires to remain viewable offline are cached here: closet items,
//  outfits, and daily briefs — plus the offline mutation queue itself.
//  Everything else (Style Studio history, product evaluations) is treated
//  as network-first and simply not cached.
//
//  KYRA THREADS ARE NETWORK-FIRST BY DECISION, NOT BY OMISSION
//  (P5-KYRA-18). The offline-cache criterion was weighed both ways and
//  this is the recorded answer. A conversation with Kyra is generative:
//  everything the screen can do — send, retry, act on a card — needs the
//  network (spec §7 puts generative features behind connectivity), so a
//  cached thread is a read-only transcript whose one use is rereading old
//  advice. And that transcript would misrepresent itself offline: Kyra's
//  messages carry cards that are ID references (`outfit_id`,
//  `product_candidate_id` — see `supabase/functions/kyra/schema.ts`)
//  hydrated at render time, and product candidates/evaluations are
//  themselves not cached, so an offline transcript renders as prose with
//  holes where its substance was. Caching the referenced rows too would
//  mean mirroring most of the shopping domain to keep one modal readable
//  on the subway — cost far out of proportion to the value. What the
//  criterion is actually protecting the user from — a message composed
//  offline being silently lost or silently queued — is handled where the
//  message is composed: `KyraConversationViewModel` surfaces an explicit
//  "Kyra needs a connection" state and disables send, rather than
//  queue-and-hope. Revisit only if reread-offline becomes a real, observed
//  need; the seam is `KyraRepository`, so a cache slots in behind the
//  protocol without touching the screen.
//

import Foundation
import SwiftData

/// The first on-disk schema shipped with closet/offline persistence.
/// Keep its model list tied to the original four entity declarations.
public enum AstraSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [PersistedClosetItem.self, PersistedOutfit.self, PersistedDailyBrief.self, PersistedOfflineMutation.self]
    }
}

/// Pending scanner uploads were added after the original unversioned store.
public enum AstraSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [
            PersistedClosetItem.self,
            PersistedOutfit.self,
            PersistedDailyBrief.self,
            PersistedOfflineMutation.self,
            PersistedPendingScan.self
        ]
    }
}

/// Scanner save recovery was added in the third persisted schema revision.
public enum AstraSchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [
            PersistedClosetItem.self,
            PersistedOutfit.self,
            PersistedDailyBrief.self,
            PersistedOfflineMutation.self,
            PersistedPendingScan.self,
            PersistedScannerSave.self
        ]
    }
}

public enum AstraSchemaMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [AstraSchemaV1.self, AstraSchemaV2.self, AstraSchemaV3.self]
    }

    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: AstraSchemaV1.self, toVersion: AstraSchemaV2.self),
            .lightweight(fromVersion: AstraSchemaV2.self, toVersion: AstraSchemaV3.self)
        ]
    }
}

public enum AstraModelContainer {
    public static let schema = Schema(versionedSchema: AstraSchemaV3.self)

    /// The production, on-disk container.
    public static func live(storeURL: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: AstraSchemaMigrationPlan.self,
            configurations: [configuration]
        )
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
