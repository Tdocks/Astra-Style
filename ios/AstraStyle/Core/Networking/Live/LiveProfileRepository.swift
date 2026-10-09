//
//  LiveProfileRepository.swift
//  AstraStyle
//
//  `profiles` / `style_profiles` / `body_profiles` / `lifestyle_profiles`
//  are simple, RLS-protected, user-owned rows, so reads/writes go straight
//  through Postgrest (spec §15 RLS: `user_id = auth.uid()`). Onboarding
//  completion and Style DNA generation are orchestration calls that need
//  server-side reasoning, so those go through `AstraAPIClient` /
//  Edge Functions (spec §14).
//

import Foundation
import Supabase

public final class LiveProfileRepository: ProfileRepository, ProfileCachePurging, @unchecked Sendable {
    let apiClient: AstraAPIClient
    let supabase: SupabaseClient
    let profileWriter: any ProfileWriting
    let profileCache: any ProfileSnapshotCaching
    let offlineQueue: any OfflineMutationQueue
    let currentUserID: @Sendable () async -> UUID?
    let refreshLock = NSLock()
    var activeRefreshes: Set<String> = []

    public init(
        apiClient: AstraAPIClient,
        supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current),
        profileWriter: (any ProfileWriting)? = nil,
        profileCache: any ProfileSnapshotCaching = InMemoryProfileSnapshotCache(),
        offlineQueue: any OfflineMutationQueue = InMemoryOfflineMutationQueue(),
        currentUserID: (@Sendable () async -> UUID?)? = nil
    ) {
        self.apiClient = apiClient
        self.supabase = supabase
        self.profileWriter = profileWriter ?? SupabaseProfileWriter(supabase: supabase)
        self.profileCache = profileCache
        self.offlineQueue = offlineQueue
        self.currentUserID = currentUserID ?? { try? await supabase.auth.session.user.id }
    }

    public func fetchCurrentProfile() async throws -> Profile {
        let ownerID = try await requireOwner()
        let cached = try await pendingAwareSnapshot(for: ownerID)
        if cached.profileFetched, let profile = cached.profile {
            scheduleRefresh(table: .profile, ownerID: ownerID)
            return profile
        }
        let profile = try await profileWriter.fetchProfile(ownerID: ownerID)
        try await verifyCurrentOwner(ownerID)
        guard profile.id == ownerID else { throw AstraError.auth("That profile belongs to another account.") }
        try await profileCache.mergeRemote(.profile(profile))
        return profile
    }

    public func updateProfile(_ profile: Profile) async throws -> Profile {
        var updated = profile
        updated.updatedAt = .now
        try await queueProfileValue(.profile(updated), table: .profile)
        return updated
    }

    public func uploadProfileAvatar(_ imageData: Data) async throws -> String {
        do {
            let session = try await supabase.auth.session
            let userID = session.user.id.uuidString.lowercased()
            let path = "users/\(userID)/avatars/\(UUID().uuidString.lowercased()).jpg"
            _ = try await supabase.storage
                .from("user-content")
                .upload(path, data: imageData, options: FileOptions(contentType: "image/jpeg"))
            return path
        } catch {
            throw AstraError.network("Couldn't upload your profile photo. Check your connection and try again.")
        }
    }

    public func updateAvatarStoragePath(_ path: String?) async throws -> Profile {
        do {
            let session = try await supabase.auth.session
            return try await supabase.from("profiles")
                .update(ProfileAvatarUpdatePayload(storagePath: path))
                .eq("id", value: session.user.id)
                .select()
                .single()
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't update your profile photo.")
        }
    }

    public func deleteProfileAvatar(path: String) async throws {
        let userID: String
        do {
            let session = try await supabase.auth.session
            userID = session.user.id.uuidString.lowercased()
        } catch {
            throw AstraError.auth("Sign in again to remove your profile photo.")
        }

        let components = path.split(separator: "/").map(String.init)
        guard components.count == 4,
              components[0] == "users",
              components[1] == userID,
              components[2] == "avatars",
              components[3].lowercased().hasSuffix(".jpg"),
              UUID(uuidString: String(components[3].dropLast(4))) != nil else {
            throw AstraError.validation("That profile photo doesn't belong to your account.")
        }

        let currentProfile = try await fetchCurrentProfile()
        guard currentProfile.avatarStoragePath != path else {
            throw AstraError.validation("Your current profile photo must be cleared before its file can be removed.")
        }

        do {
            _ = try await supabase.storage.from("user-content").remove(paths: [path])
        } catch {
            throw AstraError.network("Couldn't remove your profile photo. Please try again.")
        }
    }

    public func fetchStyleProfile() async throws -> StyleProfile? {
        let ownerID = try await requireOwner()
        let cached = try await pendingAwareSnapshot(for: ownerID)
        if cached.styleFetched {
            scheduleRefresh(table: .style, ownerID: ownerID)
            return cached.styleProfile
        }
        let value = try await profileWriter.fetchStyleProfile(ownerID: ownerID)
        try await verifyCurrentOwner(ownerID)
        if let value, value.userID != ownerID { throw AstraError.auth("That style profile belongs to another account.") }
        try await profileCache.mergeRemote(value.map(ProfileSnapshotValue.style) ?? .styleMissing(ownerID: ownerID))
        return value
    }

    public func updateStyleProfile(_ styleProfile: StyleProfile) async throws -> StyleProfile {
        var updated = styleProfile
        updated.updatedAt = .now
        try await queueProfileValue(.style(updated), table: .style)
        return updated
    }

    public func fetchBodyProfile() async throws -> BodyProfile? {
        let ownerID = try await requireOwner()
        let cached = try await pendingAwareSnapshot(for: ownerID)
        if cached.bodyFetched {
            scheduleRefresh(table: .body, ownerID: ownerID)
            return cached.bodyProfile
        }
        let value = try await profileWriter.fetchBodyProfile(ownerID: ownerID)
        try await verifyCurrentOwner(ownerID)
        if let value, value.userID != ownerID { throw AstraError.auth("That body profile belongs to another account.") }
        try await profileCache.mergeRemote(value.map(ProfileSnapshotValue.body) ?? .bodyMissing(ownerID: ownerID))
        return value
    }

    public func updateBodyProfile(_ bodyProfile: BodyProfile) async throws -> BodyProfile {
        var updated = bodyProfile
        updated.updatedAt = .now
        try await queueProfileValue(.body(updated), table: .body)
        return updated
    }

    public func fetchLifestyleProfile() async throws -> LifestyleProfile? {
        let ownerID = try await requireOwner()
        let cached = try await pendingAwareSnapshot(for: ownerID)
        if cached.lifestyleFetched {
            scheduleRefresh(table: .lifestyle, ownerID: ownerID)
            return cached.lifestyleProfile
        }
        let value = try await profileWriter.fetchLifestyleProfile(ownerID: ownerID)
        try await verifyCurrentOwner(ownerID)
        if let value, value.userID != ownerID { throw AstraError.auth("That lifestyle profile belongs to another account.") }
        try await profileCache.mergeRemote(value.map(ProfileSnapshotValue.lifestyle) ?? .lifestyleMissing(ownerID: ownerID))
        return value
    }

    public func updateLifestyleProfile(_ lifestyleProfile: LifestyleProfile) async throws -> LifestyleProfile {
        var updated = lifestyleProfile
        updated.updatedAt = .now
        try await queueProfileValue(.lifestyle(updated), table: .lifestyle)
        return updated
    }

    public func completeOnboarding(_ payload: OnboardingCompletionPayload) async throws -> Profile {
        let completed = try await apiClient.send(.completeOnboarding, body: payload, as: Profile.self)
        try await profileCache.store(.profile(completed), pendingSync: false)
        try await profileCache.store(.style(payload.styleProfile), pendingSync: false)
        try await profileCache.store(.body(payload.bodyProfile), pendingSync: false)
        try await profileCache.store(.lifestyle(payload.lifestyleProfile), pendingSync: false)
        return completed
    }

    public func generateStyleDNA() async throws -> StyleDNA {
        // An empty body on purpose: the endpoint reads the profile rows this
        // repository has already written, so everything it needs is
        // server-side. Nothing the client could send would be more
        // trustworthy than what is in the database, and sending the profile
        // back would create a second source of truth for it.
        try await apiClient.send(.generateStyleDNA, body: AstraEmptyPayload(), as: StyleDNA.self)
    }

    /// Spec §15's `users/{user_id}/references/...`, in the one bucket that
    /// exists (`user-content`, private).
    ///
    /// The user id is `.lowercased()` for the same reason `uploadCaptured()`
    /// in `LiveClosetRepository` does it, and that reason cost a day the first
    /// time: the four storage policies compare `(storage.foldername(name))[2]`
    /// against `auth.uid()::text`, Postgres renders a uuid lowercase, and
    /// Swift's `UUID.uuidString` is UPPERCASE. Without this the path is
    /// well-formed, the bucket is right, and RLS still rejects the insert.
    public func uploadReferenceImage(_ imageData: Data) async throws -> String {
        do {
            let session = try await supabase.auth.session
            let userID = session.user.id.uuidString.lowercased()
            let path = "users/\(userID)/references/\(UUID().uuidString.lowercased()).jpg"
            _ = try await supabase.storage
                .from("user-content")
                .upload(path, data: imageData, options: FileOptions(cacheControl: "60", contentType: "image/jpeg"))
            return path
        } catch {
            throw AstraError.network("Couldn't upload your photo. Check your connection and try again.")
        }
    }

    public func associateReferenceImage(path: String, acknowledged: Bool) async throws -> BodyProfile {
        struct Parameters: Encodable {
            let path: String
            let acknowledged: Bool
            enum CodingKeys: String, CodingKey {
                case path = "p_path"
                case acknowledged = "p_acknowledged"
            }
        }
        do {
            return try await supabase.rpc("associate_reference_photo", params: Parameters(path: path, acknowledged: acknowledged))
                .single().execute().value
        } catch {
            throw AstraError.server("Couldn't save that reference. It may have expired or been removed. Reopen capture to try again.")
        }
    }

    public func deleteReferenceImage(path: String) async throws {
        struct Payload: Encodable, Sendable { let path: String }
        struct Result: Decodable, Sendable { let id: UUID; let status: String }
        // The server validates ownership and atomically hides the reference and
        // every derived variation. Storage failures become durable retry jobs.
        _ = try await apiClient.send(.deleteReferencePhoto, body: Payload(path: path), as: Result.self)
    }

    public func exportPersonalData() async throws -> URL {
        do {
            let export = try await apiClient.send(.exportPersonalData, as: PersonalDataExport.self)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(export)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("astra-personal-data-export.json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.server("Couldn't create your export. Please try again.")
        }
    }

    public func applyReferralCode(_ code: String) async throws {
        struct Params: Encodable, Sendable {
            let code: String
            enum CodingKeys: String, CodingKey {
                case code = "p_code"
            }
        }
        do {
            try await supabase
                .rpc("apply_referral_code", params: Params(code: code))
                .execute()
        } catch {
            throw AstraError.validation(error.localizedDescription)
        }
    }

}

private struct ProfileAvatarUpdatePayload: Encodable, Sendable {
    let storagePath: String?

    enum CodingKeys: String, CodingKey {
        case storagePath = "avatar_storage_path"
        case avatarURL = "avatar_url"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storagePath, forKey: .storagePath)
        try container.encodeNil(forKey: .avatarURL)
    }
}
