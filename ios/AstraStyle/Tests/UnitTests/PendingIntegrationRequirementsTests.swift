//
//  PendingIntegrationRequirementsTests.swift
//  AstraStyleTests
//
//  Spec §22 lists several integration tests that genuinely cannot be
//  written yet — they require a live Supabase project, deployed Edge
//  Functions, a configured StoreKit sandbox, and/or a running AI provider,
//  none of which exist in this scaffold. Per the build instructions, these
//  are represented as INTENTIONALLY FAILING placeholders rather than
//  silently omitted, so the gap is visible in CI/Xcode's test navigator
//  instead of invisible.
//
//  DO NOT mark these `.disabled()` or delete them to make CI green — each
//  one should be replaced with a real integration test (and only then
//  removed from this file) as its backing infrastructure lands. The
//  `Issue.record` message names the spec requirement and the ticket
//  prefix expected to close it.
//

import Testing
@testable import AstraStyle

@Suite("Pending integration requirements (spec §22) — intentionally failing until implemented")
struct PendingIntegrationRequirementsTests {

    @Test("Auth lifecycle: sign in, session refresh, sign out against a real Supabase project")
    func authLifecycle() {
        Issue.record(
            "Not implemented: requires a live Supabase Auth project and a way to drive Sign in with Apple / email OTP in a test target. Owner: P1-CORE / P2-ONBOARD. Spec §22 'Integration tests: Auth lifecycle'."
        )
    }

    @Test("Closet upload and sync: capture -> analyze -> save round trip against live Storage + Postgrest")
    func closetUploadAndSync() {
        Issue.record(
            "Not implemented: requires a deployed `closet/analyze-item` Edge Function and a live Storage bucket. Owner: P3-CLOSET / P3-SCAN. Spec §22 'Integration tests: Closet upload and sync'."
        )
    }

    @Test("Daily Brief generation against a live `daily-brief/generate` Edge Function")
    func dailyBriefGeneration() {
        Issue.record(
            "Not implemented: requires a deployed Edge Function backed by a live StylistReasoningProvider + weather provider. Owner: P4-OUTFIT. Spec §22 'Integration tests: Daily Brief generation'."
        )
    }

    @Test("Product evaluation against a live `products/evaluate` Edge Function")
    func productEvaluation() {
        Issue.record(
            "Not implemented: requires a deployed Edge Function and a seeded product_candidates table. Owner: P6-SHOP. Spec §22 'Integration tests: Product evaluation'."
        )
    }

    @Test("Style Studio job polling against a live `studio/generate` + `studio/status/:id` pair")
    func studioJobPolling() {
        Issue.record(
            "Not implemented: requires a deployed Edge Function and a live ImageGenerationProvider. Owner: P6-STUDIO. Spec §22 'Integration tests: Studio job polling'."
        )
    }

    @Test("StoreKit sandbox purchase and server-side reconciliation")
    func storeKitSandboxPurchase() {
        Issue.record(
            "Not implemented: requires a StoreKit configuration file / sandbox tester account and a deployed `subscriptions/sync` Edge Function. Owner: P7-SUB. Spec §22 'Integration tests: StoreKit sandbox purchase'."
        )
    }

    @Test("Snapshot tests: major screens in light/dark mode across Dynamic Type sizes")
    func snapshotTestsNotYetConfigured() {
        Issue.record(
            "Not implemented: no snapshot-testing library is wired into the project yet (spec doesn't mandate one; a follow-up decision — swift-snapshot-testing is the likely candidate). Spec §22 'Snapshot tests'."
        )
    }
}
