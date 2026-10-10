//
//  AstraEnvironment.swift
//  AstraStyle
//
//  Reads the two client-safe values permitted by spec §25
//  (SUPABASE_URL, SUPABASE_ANON_KEY) out of the app bundle's Info.plist,
//  where they were placed by the `$(SUPABASE_URL)` / `$(SUPABASE_ANON_KEY)`
//  build-setting substitutions declared in project.yml and ultimately
//  sourced from Config/Secrets.xcconfig (gitignored; see
//  Config/Secrets.example.xcconfig).
//
//  This is the only place in the app that reads those values directly —
//  everything else receives an already-configured `AstraAPIClient`.
//

import Foundation

public struct AstraEnvironment: Sendable {
    public let supabaseURL: URL
    public let supabaseAnonKey: String
    public let isLocalQABackend: Bool

    public init(supabaseURL: URL, supabaseAnonKey: String, isLocalQABackend: Bool = false) {
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.isLocalQABackend = isLocalQABackend
    }

    /// Edge Functions live under `/functions/v1/` on the Supabase project
    /// URL (spec §14).
    public var edgeFunctionsBaseURL: URL {
        supabaseURL.appendingPathComponent("functions/v1")
    }

    /// Reads `SUPABASE_URL` / `SUPABASE_ANON_KEY` from the app's own
    /// Info.plist. Crashes at launch with a clear message if secrets were
    /// never configured — this is a build-time misconfiguration, not a
    /// runtime condition the app can recover from, so failing loudly during
    /// development is preferable to shipping a client that silently can't
    /// reach the backend.
    public static let current: AstraEnvironment = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-astra-local-qa-kyra") {
            return localQAEnvironment()
        }
        #endif

        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            !urlString.isEmpty,
            !urlString.hasPrefix("YOUR-"),
            let url = URL(string: urlString)
        else {
            preconditionFailure(
                "SUPABASE_URL is missing or still a placeholder. Copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig and fill in your project's values, then re-run `xcodegen generate`."
            )
        }
        guard
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !anonKey.isEmpty,
            !anonKey.hasPrefix("YOUR-")
        else {
            preconditionFailure(
                "SUPABASE_ANON_KEY is missing or still a placeholder. Copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig and fill in your project's values, then re-run `xcodegen generate`."
            )
        }
        return AstraEnvironment(supabaseURL: url, supabaseAnonKey: anonKey)
    }()

    #if DEBUG
    private static func localQAEnvironment() -> AstraEnvironment {
        let values = ProcessInfo.processInfo.environment
        guard
            let urlString = values["ASTRA_LOCAL_SUPABASE_URL"],
            let url = URL(string: urlString),
            isLoopbackHTTPURL(url),
            let anonKey = values["ASTRA_LOCAL_SUPABASE_ANON_KEY"],
            !anonKey.isEmpty
        else {
            preconditionFailure("Local Kyra QA requires a loopback Supabase URL and its local anon key.")
        }
        return AstraEnvironment(supabaseURL: url, supabaseAnonKey: anonKey, isLocalQABackend: true)
    }

    private static func isLoopbackHTTPURL(_ url: URL) -> Bool {
        guard
            url.scheme?.lowercased() == "http",
            url.user == nil,
            url.password == nil,
            url.query == nil,
            url.fragment == nil
        else { return false }
        let host = url.host?.lowercased()
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
    #endif

    /// A safe, non-crashing environment for SwiftUI previews and unit
    /// tests, which never have a real Info.plist configured.
    public static let preview = AstraEnvironment(
        // `URL(string:)` only fails on malformed input; this literal is
        // fixed and known-valid, but we still avoid `!` per house style by
        // falling back to a guaranteed-valid `file://` URL rather than
        // force-unwrapping.
        supabaseURL: URL(string: "https://preview.supabase.co") ?? URL(fileURLWithPath: "/preview.supabase.co"),
        supabaseAnonKey: "preview-anon-key"
    )
}
