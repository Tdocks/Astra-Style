//
//  PendingIntegrationRequirementsTests.swift
//  AstraStyleTests
//
//  Spec §22 lists several integration tests that genuinely cannot be
//  written yet — they require a live Supabase project, deployed Edge
//  Functions, a configured StoreKit sandbox, and/or a running AI provider,
//  none of which exist in this scaffold. They are represented here as
//  explicitly SKIPPED tests rather than silently omitted, so the gap stays
//  visible in Xcode's test navigator and in CI's test report.
//
//  These were originally written as `Issue.record(...)` bodies — deliberate
//  failures, so the gap would be impossible to miss. That was replaced with
//  `.disabled(reason:)` for one reason: a suite that can never be green is a
//  suite nobody reads. Seven permanent red tests do not communicate "seven
//  things are missing", they communicate "this job is always red", and they
//  make every OTHER failure — a real regression, the P1-INFRA-03 requirement
//  that CI fails on a warning or lint violation — unverifiable, because the
//  job was already failing. A skip with a stated reason says exactly the same
//  thing, in the place a reader looks for it, without spending the signal.
//
//  `.disabled` rather than `withKnownIssue` for all seven: `withKnownIssue`
//  is for a test that genuinely RUNS and genuinely fails, and that should
//  start failing the moment it stops failing. None of these bodies contain a
//  single assertion — there is nothing to run, so there is no known issue to
//  observe, only work that has not started. "Disabled, with a stated reason"
//  is what these actually are.
//
//  DO NOT delete these to make CI green — a deleted requirement is an
//  invisible one. Each should be replaced with a real integration test (and
//  the `.disabled` trait dropped at that point, not before) as its backing
//  infrastructure lands. The `.disabled` reason names the spec requirement
//  and the ticket prefix expected to close it.
//

import Testing
@testable import AstraStyle

@Suite("Pending integration requirements (spec §22) — skipped until their backing infrastructure exists")
struct PendingIntegrationRequirementsTests {

    @Test(
        "Auth lifecycle: sign in, session refresh, sign out against a real Supabase project",
        .disabled(
            "Not implemented: requires a live Supabase Auth project and a way to drive Sign in with Apple / email OTP in a test target. Owner: P1-CORE / P2-ONBOARD. Spec §22 'Integration tests: Auth lifecycle'."
        )
    )
    func authLifecycle() {
        // Intentionally empty: the `.disabled` reason above IS the report.
        // Replace this body with the real integration test and remove the trait.
    }

    @Test(
        "Closet upload and sync: capture -> analyze -> save round trip against live Storage + Postgrest",
        .disabled(
            "Not implemented: requires a deployed `closet/analyze-item` Edge Function and a live Storage bucket. Owner: P3-CLOSET / P3-SCAN. Spec §22 'Integration tests: Closet upload and sync'."
        )
    )
    func closetUploadAndSync() {
        // Intentionally empty: the `.disabled` reason above IS the report.
        // Replace this body with the real integration test and remove the trait.
    }

    @Test(
        "Daily Brief generation against a live `daily-brief/generate` Edge Function",
        .disabled(
            "Not implemented: requires a deployed Edge Function backed by a live StylistReasoningProvider + weather provider. Owner: P4-OUTFIT. Spec §22 'Integration tests: Daily Brief generation'."
        )
    )
    func dailyBriefGeneration() {
        // Intentionally empty: the `.disabled` reason above IS the report.
        // Replace this body with the real integration test and remove the trait.
    }

    @Test(
        "Product evaluation against a live `products/evaluate` Edge Function",
        .disabled(
            "Not implemented: requires a deployed Edge Function and a seeded product_candidates table. Owner: P6-SHOP. Spec §22 'Integration tests: Product evaluation'."
        )
    )
    func productEvaluation() {
        // Intentionally empty: the `.disabled` reason above IS the report.
        // Replace this body with the real integration test and remove the trait.
    }

    @Test(
        "Style Studio job polling against a live `studio/generate` + `studio/status/:id` pair",
        .disabled(
            "Not implemented: requires a deployed Edge Function and a live ImageGenerationProvider. Owner: P6-STUDIO. Spec §22 'Integration tests: Studio job polling'."
        )
    )
    func studioJobPolling() {
        // Intentionally empty: the `.disabled` reason above IS the report.
        // Replace this body with the real integration test and remove the trait.
    }

    @Test(
        "StoreKit sandbox purchase and server-side reconciliation",
        .disabled(
            "Not implemented: requires a StoreKit configuration file / sandbox tester account and a deployed `subscriptions/sync` Edge Function. Owner: P7-SUB. Spec §22 'Integration tests: StoreKit sandbox purchase'."
        )
    )
    func storeKitSandboxPurchase() {
        // Intentionally empty: the `.disabled` reason above IS the report.
        // Replace this body with the real integration test and remove the trait.
    }

    @Test(
        "Snapshot tests: major screens in light/dark mode across Dynamic Type sizes",
        .disabled(
            "Not implemented: no snapshot-testing library is wired into the project yet (spec doesn't mandate one; a follow-up decision — swift-snapshot-testing is the likely candidate). Spec §22 'Snapshot tests'."
        )
    )
    func snapshotTestsNotYetConfigured() {
        // Intentionally empty: the `.disabled` reason above IS the report.
        // Replace this body with the real snapshot tests and remove the trait.
    }

    @Test(
        "Account deletion end-to-end: DELETE /account against a live Supabase project, through the Storage purge and auth.admin.deleteUser cascade to a completed account_deletions row",
        .disabled(
            "Not implemented: requires a live Supabase project with the account Edge Function deployed and service-role credentials to observe the cascade's terminal state. AccountDeletionViewModelTests covers the client-side flow against a fake AuthRepository; this is the missing live-backend half. Owner: P7-PRIVACY-01/02. Spec §22 'Integration tests'."
        )
    )
    func accountDeletionEndToEnd() {
        // Intentionally empty: the `.disabled` reason above IS the report.
        // Replace this body with the real integration test and remove the trait.
    }

    @Test(
        "Personal data export: a signed export URL that resolves to a real, current snapshot of the user's data",
        .disabled(
            "Not implemented: there is no export Edge Function, scheduled job, or `exports` storage bucket anywhere in this codebase — `LiveProfileRepository.exportPersonalData()` signs a URL for an object nothing ever writes. No UI was built on top of it either (Features/Profile/README.md), per spec §22's 'no dead buttons'. Owner: P7-PRIVACY-03. Spec §29 'Export personal data'."
        )
    )
    func personalDataExportEndToEnd() {
        // Intentionally empty: the `.disabled` reason above IS the report.
        // Replace this body with the real integration test and remove the trait.
    }
}
