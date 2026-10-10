//
//  AstraSupabaseClientFactory.swift
//  AstraStyle
//
//  Constructs the shared `Supabase.SupabaseClient` used for the pieces of
//  the stack that Supabase's own SDK handles directly rather than through
//  a custom Edge Function: Auth (Sign in with Apple / email OTP / session
//  refresh — spec §7), direct Postgrest table access on user-owned tables
//  protected by Row Level Security (spec §15), and Storage signed uploads
//  for closet/reference/studio images (spec §15 storage paths).
//
//  `AstraAPIClient` remains the ONLY path to the 16 orchestration
//  endpoints in spec §14 (outfit generation, Kyra, product evaluation,
//  Style Studio, etc) — those require server-side provider keys the client
//  must never see, so they are deliberately not reachable through this
//  client's Postgrest/Storage surfaces.
//

import Foundation
import Supabase

public enum AstraSupabaseClientFactory {
    public static func make(environment: AstraEnvironment) -> SupabaseClient {
        #if DEBUG
        if environment.isLocalQABackend {
            return SupabaseClient(
                supabaseURL: environment.supabaseURL,
                supabaseKey: environment.supabaseAnonKey,
                options: SupabaseClientOptions(
                    auth: .init(storage: localQAAuthStorage())
                )
            )
        }
        #endif
        return SupabaseClient(
            supabaseURL: environment.supabaseURL,
            supabaseKey: environment.supabaseAnonKey
        )
    }

    #if DEBUG
    /// All SDK clients in one local QA app process must observe the same
    /// session. Live repositories construct separate SupabaseClient values;
    /// per-client stores made Kyra and closet requests look signed out after
    /// SessionStore installed the fixture session. This store is memory-only
    /// and available only when the explicit loopback QA launch mode is active.
    static func localQAAuthStorage() -> AuthLocalStorage {
        return sharedLocalQAAuthStorage
    }

    private static let sharedLocalQAAuthStorage = LocalQAVolatileAuthStorage()
    #endif

    /// A client safe to construct for SwiftUI previews / tests. Like
    /// `AstraAPIClient.previewClient`, it is never actually invoked in
    /// preview builds because `AppContainer.preview()` wires repositories
    /// to in-memory mocks instead.
    public static let previewClient = make(environment: .preview)
}

#if DEBUG
/// Supabase SDK auth state for local UI fixtures must die with the app
/// process. All SDK clients share this instance. The lock protects synchronous
/// storage callbacks from concurrent auth requests; no fixture credential
/// reaches Keychain or disk.
private final class LocalQAVolatileAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.withLock { values[key] = value }
    }

    func retrieve(key: String) throws -> Data? {
        lock.withLock { values[key] }
    }

    func remove(key: String) throws {
        lock.withLock { values[key] = nil }
    }
}
#endif
