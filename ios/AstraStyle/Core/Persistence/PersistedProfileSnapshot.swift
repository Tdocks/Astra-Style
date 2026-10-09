import Foundation
import SwiftData

@Model
public final class PersistedProfileSnapshot {
    @Attribute(.unique) public var ownerID: UUID
    public var profileData: Data?
    public var styleProfileData: Data?
    public var bodyProfileData: Data?
    public var lifestyleProfileData: Data?
    public var profileFetched: Bool
    public var styleFetched: Bool
    public var bodyFetched: Bool
    public var lifestyleFetched: Bool
    public var pendingProfileSync: Bool
    public var pendingStyleSync: Bool
    public var pendingBodySync: Bool
    public var pendingLifestyleSync: Bool
    public var cachedAt: Date

    public init(ownerID: UUID, cachedAt: Date = .now) {
        self.ownerID = ownerID
        self.profileData = nil
        self.styleProfileData = nil
        self.bodyProfileData = nil
        self.lifestyleProfileData = nil
        self.profileFetched = false
        self.styleFetched = false
        self.bodyFetched = false
        self.lifestyleFetched = false
        self.pendingProfileSync = false
        self.pendingStyleSync = false
        self.pendingBodySync = false
        self.pendingLifestyleSync = false
        self.cachedAt = cachedAt
    }
}

@ModelActor
public actor SwiftDataProfileSnapshotCache: ProfileSnapshotCaching {
    public func snapshot(for ownerID: UUID) async throws -> ProfileSnapshot? {
        let descriptor = FetchDescriptor<PersistedProfileSnapshot>(predicate: #Predicate { $0.ownerID == ownerID })
        guard let row = try modelContext.fetch(descriptor).first else { return nil }
        return try Self.domainSnapshot(from: row)
    }

    public func store(_ value: ProfileSnapshotValue, pendingSync: Bool) async throws {
        let (row, inserted) = try row(for: value.ownerID)
        let previous = Self.state(of: row)
        do {
            try Self.apply(value, to: row, pending: pendingSync)
            row.cachedAt = .now
            try modelContext.save()
        } catch {
            if inserted { modelContext.delete(row) } else { Self.restore(previous, to: row) }
            throw error
        }
    }

    public func mergeRemote(_ value: ProfileSnapshotValue) async throws {
        let (row, inserted) = try row(for: value.ownerID)
        let isPending: Bool
        switch value {
        case .profile: isPending = row.pendingProfileSync
        case .style, .styleMissing: isPending = row.pendingStyleSync
        case .body, .bodyMissing: isPending = row.pendingBodySync
        case .lifestyle, .lifestyleMissing: isPending = row.pendingLifestyleSync
        }
        if !isPending {
            let previous = Self.state(of: row)
            do {
                try Self.apply(value, to: row, pending: false)
                row.cachedAt = .now
                try modelContext.save()
            } catch {
                if inserted { modelContext.delete(row) } else { Self.restore(previous, to: row) }
                throw error
            }
        } else if inserted {
            modelContext.delete(row)
        }
    }

    public func removeAll(ownerID: UUID) async throws {
        let descriptor = FetchDescriptor<PersistedProfileSnapshot>(predicate: #Predicate { $0.ownerID == ownerID })
        let rows = try modelContext.fetch(descriptor)
        for row in rows { modelContext.delete(row) }
        do {
            try modelContext.save()
        } catch {
            for row in rows { modelContext.insert(row) }
            throw error
        }
    }

    private func row(for ownerID: UUID) throws -> (PersistedProfileSnapshot, Bool) {
        let descriptor = FetchDescriptor<PersistedProfileSnapshot>(predicate: #Predicate { $0.ownerID == ownerID })
        if let existing = try modelContext.fetch(descriptor).first { return (existing, false) }
        let created = PersistedProfileSnapshot(ownerID: ownerID)
        modelContext.insert(created)
        return (created, true)
    }

    private struct RowState {
        let profileData: Data?
        let styleProfileData: Data?
        let bodyProfileData: Data?
        let lifestyleProfileData: Data?
        let profileFetched: Bool
        let styleFetched: Bool
        let bodyFetched: Bool
        let lifestyleFetched: Bool
        let pendingProfileSync: Bool
        let pendingStyleSync: Bool
        let pendingBodySync: Bool
        let pendingLifestyleSync: Bool
        let cachedAt: Date
    }

    private static func state(of row: PersistedProfileSnapshot) -> RowState {
        RowState(
            profileData: row.profileData,
            styleProfileData: row.styleProfileData,
            bodyProfileData: row.bodyProfileData,
            lifestyleProfileData: row.lifestyleProfileData,
            profileFetched: row.profileFetched,
            styleFetched: row.styleFetched,
            bodyFetched: row.bodyFetched,
            lifestyleFetched: row.lifestyleFetched,
            pendingProfileSync: row.pendingProfileSync,
            pendingStyleSync: row.pendingStyleSync,
            pendingBodySync: row.pendingBodySync,
            pendingLifestyleSync: row.pendingLifestyleSync,
            cachedAt: row.cachedAt
        )
    }

    private static func restore(_ state: RowState, to row: PersistedProfileSnapshot) {
        row.profileData = state.profileData
        row.styleProfileData = state.styleProfileData
        row.bodyProfileData = state.bodyProfileData
        row.lifestyleProfileData = state.lifestyleProfileData
        row.profileFetched = state.profileFetched
        row.styleFetched = state.styleFetched
        row.bodyFetched = state.bodyFetched
        row.lifestyleFetched = state.lifestyleFetched
        row.pendingProfileSync = state.pendingProfileSync
        row.pendingStyleSync = state.pendingStyleSync
        row.pendingBodySync = state.pendingBodySync
        row.pendingLifestyleSync = state.pendingLifestyleSync
        row.cachedAt = state.cachedAt
    }

    private static func domainSnapshot(from row: PersistedProfileSnapshot) throws -> ProfileSnapshot {
        let decoder = ProfileSnapshotCoding.makeDecoder()
        let profile = try row.profileData.map { try decoder.decode(Profile.self, from: $0) }
        let style = try row.styleProfileData.map { try decoder.decode(StyleProfile.self, from: $0) }
        let body = try row.bodyProfileData.map { try decoder.decode(BodyProfile.self, from: $0) }
        let lifestyle = try row.lifestyleProfileData.map { try decoder.decode(LifestyleProfile.self, from: $0) }
        guard profile?.id == nil || profile?.id == row.ownerID,
              style?.userID == nil || style?.userID == row.ownerID,
              body?.userID == nil || body?.userID == row.ownerID,
              lifestyle?.userID == nil || lifestyle?.userID == row.ownerID else {
            throw AstraError.auth("Cached profile data belongs to another account.")
        }
        return ProfileSnapshot(
            profile: profile,
            styleProfile: style,
            bodyProfile: body,
            lifestyleProfile: lifestyle,
            profileFetched: row.profileFetched,
            styleFetched: row.styleFetched,
            bodyFetched: row.bodyFetched,
            lifestyleFetched: row.lifestyleFetched,
            pendingProfile: row.pendingProfileSync,
            pendingStyle: row.pendingStyleSync,
            pendingBody: row.pendingBodySync,
            pendingLifestyle: row.pendingLifestyleSync
        )
    }

    private static func apply(_ value: ProfileSnapshotValue, to row: PersistedProfileSnapshot, pending: Bool) throws {
        guard value.ownerID == row.ownerID else {
            throw AstraError.auth("Profile data belongs to another account.")
        }
        let encoder = ProfileSnapshotCoding.makeEncoder()
        switch value {
        case .profile(let profile):
            row.profileData = try encoder.encode(profile)
            row.profileFetched = true
            row.pendingProfileSync = pending
        case .style(let profile):
            row.styleProfileData = try encoder.encode(profile)
            row.styleFetched = true
            row.pendingStyleSync = pending
        case .body(let profile):
            row.bodyProfileData = try encoder.encode(profile)
            row.bodyFetched = true
            row.pendingBodySync = pending
        case .lifestyle(let profile):
            row.lifestyleProfileData = try encoder.encode(profile)
            row.lifestyleFetched = true
            row.pendingLifestyleSync = pending
        case .styleMissing:
            row.styleProfileData = nil
            row.styleFetched = true
            row.pendingStyleSync = pending
        case .bodyMissing:
            row.bodyProfileData = nil
            row.bodyFetched = true
            row.pendingBodySync = pending
        case .lifestyleMissing:
            row.lifestyleProfileData = nil
            row.lifestyleFetched = true
            row.pendingLifestyleSync = pending
        }
    }
}
