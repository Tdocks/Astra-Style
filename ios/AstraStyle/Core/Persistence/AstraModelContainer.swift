//
//  AstraModelContainer.swift
//  AstraStyle
//
//  Central SwiftData schema/container factory (spec §8 "SwiftData for
//  local cache and offline-first entities"). Only the entities spec §7
//  requires to remain viewable offline are cached here: closet items,
//  outfits, and daily briefs — plus the offline mutation queue itself.
//  Style Studio remains network-first. Server-confirmed Kyra transcripts
//  and product evaluations are cached only for explicit offline reading;
//  neither is used to replay requests or create a fresh recommendation.

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

/// Owner-scoped cached profile tables and per-table pending-sync state.
public enum AstraSchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [
            PersistedClosetItem.self,
            PersistedOutfit.self,
            PersistedDailyBrief.self,
            PersistedOfflineMutation.self,
            PersistedPendingScan.self,
            PersistedScannerSave.self,
            PersistedProfileSnapshot.self
        ]
    }
}

/// Owner-scoped Kyra transcripts and dated product-decision snapshots;
/// V4 stores migrate without changing existing persisted rows.
public enum AstraSchemaV5: VersionedSchema {
    public static let versionIdentifier = Schema.Version(5, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [
            PersistedClosetItem.self,
            PersistedOutfit.self,
            PersistedDailyBrief.self,
            PersistedOfflineMutation.self,
            PersistedPendingScan.self,
            PersistedScannerSave.self,
            PersistedProfileSnapshot.self,
            PersistedKyraThreadListSnapshot.self,
            PersistedKyraThread.self,
            PersistedKyraMessage.self,
            PersistedProductEvaluation.self
        ]
    }
}

public enum AstraSchemaMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [AstraSchemaV1.self, AstraSchemaV2.self, AstraSchemaV3.self, AstraSchemaV4.self, AstraSchemaV5.self]
    }

    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: AstraSchemaV1.self, toVersion: AstraSchemaV2.self),
            .lightweight(fromVersion: AstraSchemaV2.self, toVersion: AstraSchemaV3.self),
            .lightweight(fromVersion: AstraSchemaV3.self, toVersion: AstraSchemaV4.self),
            .lightweight(fromVersion: AstraSchemaV4.self, toVersion: AstraSchemaV5.self)
        ]
    }
}

public enum AstraModelContainer {
    public static let schema = Schema(versionedSchema: AstraSchemaV5.self)

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
