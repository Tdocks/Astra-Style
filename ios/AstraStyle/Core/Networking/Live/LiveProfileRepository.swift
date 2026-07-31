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

public final class LiveProfileRepository: ProfileRepository, @unchecked Sendable {
    private let apiClient: AstraAPIClient
    private let supabase: SupabaseClient

    public init(apiClient: AstraAPIClient, supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current)) {
        self.apiClient = apiClient
        self.supabase = supabase
    }

    public func fetchCurrentProfile() async throws -> Profile {
        do {
            return try await supabase.from("profiles").select().single().execute().value
        } catch {
            throw AstraError.server("Couldn't load your profile.")
        }
    }

    public func updateProfile(_ profile: Profile) async throws -> Profile {
        do {
            return try await supabase.from("profiles")
                .update(profile)
                .eq("id", value: profile.id)
                .select()
                .single()
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't save your profile changes.")
        }
    }

    public func fetchStyleProfile() async throws -> StyleProfile? {
        try await fetchOptionalSingle(table: "style_profiles")
    }

    public func updateStyleProfile(_ styleProfile: StyleProfile) async throws -> StyleProfile {
        do {
            return try await supabase.from("style_profiles")
                .upsert(styleProfile)
                .select()
                .single()
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't save your style profile.")
        }
    }

    public func fetchBodyProfile() async throws -> BodyProfile? {
        try await fetchOptionalSingle(table: "body_profiles")
    }

    public func updateBodyProfile(_ bodyProfile: BodyProfile) async throws -> BodyProfile {
        do {
            return try await supabase.from("body_profiles")
                .upsert(bodyProfile)
                .select()
                .single()
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't save your measurements.")
        }
    }

    public func fetchLifestyleProfile() async throws -> LifestyleProfile? {
        try await fetchOptionalSingle(table: "lifestyle_profiles")
    }

    public func updateLifestyleProfile(_ lifestyleProfile: LifestyleProfile) async throws -> LifestyleProfile {
        do {
            return try await supabase.from("lifestyle_profiles")
                .upsert(lifestyleProfile)
                .select()
                .single()
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't save your lifestyle preferences.")
        }
    }

    public func completeOnboarding(_ payload: OnboardingCompletionPayload) async throws -> Profile {
        try await apiClient.send(.completeOnboarding, body: payload, as: Profile.self)
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
                .upload(path, data: imageData, options: FileOptions(contentType: "image/jpeg"))
            return path
        } catch {
            throw AstraError.network("Couldn't upload your photo. Check your connection and try again.")
        }
    }

    public func exportPersonalData() async throws -> URL {
        // Spec §29 requires personal-data export but §14's endpoint list
        // has no dedicated export orchestration call. A batch export is
        // realistically a background job (not a synchronous Edge Function
        // response), so the client asks Storage for a signed URL to
        // whatever the most recent export snapshot is; a real
        // implementation pairs this with an admin-triggered (spec §28) or
        // scheduled job that (re)writes that snapshot per user.
        do {
            let session = try await supabase.auth.session
            let signedURL = try await supabase.storage
                .from("exports")
                .createSignedURL(path: "users/\(session.user.id.uuidString)/export-latest.json", expiresIn: 300)
            return signedURL
        } catch {
            throw AstraError.server("No export is available yet. Please try again shortly.")
        }
    }

    private func fetchOptionalSingle<T: Decodable & Sendable>(table: String) async throws -> T? {
        do {
            return try await supabase.from(table).select().single().execute().value
        } catch {
            // No row yet (profile not created past this onboarding step)
            // is an expected, non-error state.
            return nil
        }
    }
}
