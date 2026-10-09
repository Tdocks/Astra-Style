import Foundation
import Supabase

public protocol ProfileWriting: Sendable {
    func fetchProfile(ownerID: UUID) async throws -> Profile
    func fetchStyleProfile(ownerID: UUID) async throws -> StyleProfile?
    func fetchBodyProfile(ownerID: UUID) async throws -> BodyProfile?
    func fetchLifestyleProfile(ownerID: UUID) async throws -> LifestyleProfile?
    func updateProfile(_ value: Profile) async throws -> Profile
    func upsertStyleProfile(_ value: StyleProfile) async throws -> StyleProfile
    func upsertBodyProfile(_ value: BodyProfile) async throws -> BodyProfile
    func upsertLifestyleProfile(_ value: LifestyleProfile) async throws -> LifestyleProfile
}

struct SupabaseProfileWriter: ProfileWriting {
    let supabase: SupabaseClient

    public func fetchProfile(ownerID: UUID) async throws -> Profile {
        try await supabase.from("profiles")
            .select()
            .eq("id", value: ownerID)
            .single()
            .execute()
            .value
    }

    public func fetchStyleProfile(ownerID: UUID) async throws -> StyleProfile? {
        let rows: [StyleProfile] = try await supabase.from("style_profiles")
            .select()
            .eq("user_id", value: ownerID)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    public func fetchBodyProfile(ownerID: UUID) async throws -> BodyProfile? {
        let rows: [BodyProfile] = try await supabase.from("body_profiles")
            .select()
            .eq("user_id", value: ownerID)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    public func fetchLifestyleProfile(ownerID: UUID) async throws -> LifestyleProfile? {
        let rows: [LifestyleProfile] = try await supabase.from("lifestyle_profiles")
            .select()
            .eq("user_id", value: ownerID)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    public func updateProfile(_ value: Profile) async throws -> Profile {
        try await supabase.from("profiles")
            .update(value)
            .eq("id", value: value.id)
            .select()
            .single()
            .execute()
            .value
    }

    public func upsertStyleProfile(_ value: StyleProfile) async throws -> StyleProfile {
        try await supabase.from("style_profiles")
            .upsert(value)
            .select()
            .single()
            .execute()
            .value
    }

    public func upsertBodyProfile(_ value: BodyProfile) async throws -> BodyProfile {
        try await supabase.from("body_profiles")
            .upsert(value)
            .select()
            .single()
            .execute()
            .value
    }

    public func upsertLifestyleProfile(_ value: LifestyleProfile) async throws -> LifestyleProfile {
        try await supabase.from("lifestyle_profiles")
            .upsert(value)
            .select()
            .single()
            .execute()
            .value
    }
}
