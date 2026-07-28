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
        SupabaseClient(
            supabaseURL: environment.supabaseURL,
            supabaseKey: environment.supabaseAnonKey
        )
    }

    /// A client safe to construct for SwiftUI previews / tests. Like
    /// `AstraAPIClient.previewClient`, it is never actually invoked in
    /// preview builds because `AppContainer.preview()` wires repositories
    /// to in-memory mocks instead.
    public static let previewClient = make(environment: .preview)
}
