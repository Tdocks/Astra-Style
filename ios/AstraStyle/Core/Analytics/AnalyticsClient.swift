//
//  AnalyticsClient.swift
//  AstraStyle
//
//  Protocol-based analytics boundary (spec §18). `LiveAnalyticsClient` is
//  where a real SDK (e.g. a privacy-preserving first-party pipeline
//  through an Edge Function, per spec §18's preference) would be wired in;
//  `NoOpAnalyticsClient` backs previews/tests so no event ever needs
//  network in those contexts.
//

import Foundation

public protocol AnalyticsClient: Sendable {
    func log(_ event: AnalyticsEvent)

    /// Associates the analytics identity with the signed-in user. Called
    /// once after sign-in; never carries PII beyond the opaque user id —
    /// display name, email, and images are never sent to analytics.
    func identify(userID: UUID)

    /// Clears the analytics identity on sign-out (spec §29 privacy
    /// posture: don't keep correlating events with a signed-out user).
    func reset()
}

/// Production conformance. Wraps the event in the privacy guard from
/// spec §18 ("do not expose sensitive images or free-text prompts") before
/// forwarding it — `AnalyticsEvent.properties` already excludes those by
/// construction, but this is where a second, defense-in-depth scrub would
/// live if a future event type ever risked carrying free text.
public final class LiveAnalyticsClient: AnalyticsClient, @unchecked Sendable {
    public init() {}

    public func log(_ event: AnalyticsEvent) {
        // Wired to a real analytics SDK / first-party ingestion endpoint
        // once one is selected (spec §18 "Prefer external analytics SDK or
        // privacy-preserving first-party events"). Until then this is
        // intentionally inert rather than silently dropping events without
        // a trace during development.
        #if DEBUG
        print("[Analytics] \(event.name) \(event.properties)")
        #endif
    }

    public func identify(userID: UUID) {
        #if DEBUG
        print("[Analytics] identify \(userID)")
        #endif
    }

    public func reset() {
        #if DEBUG
        print("[Analytics] reset")
        #endif
    }
}

/// Used by `AppContainer.preview()` and unit tests — swallows every call.
public struct NoOpAnalyticsClient: AnalyticsClient {
    public init() {}
    public func log(_ event: AnalyticsEvent) {}
    public func identify(userID: UUID) {}
    public func reset() {}
}
