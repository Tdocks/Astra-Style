//
//  PendingIntegrationRequirementsTests.swift
//  AstraStyleTests
//
//  Spec §22 lists connected integration requirements that are not implemented
//  as these native test cases. The project now has a live Supabase deployment
//  and focused hosted acceptance harnesses. Those prove their named backend
//  paths, not a continuous signed-in iOS journey. StoreKit sandbox,
//  physical-device, and provider-cost requirements remain separate gates.
//  These placeholders stay disabled so the requirements remain visible.
//
//  These bodies intentionally have no assertions. Keep them disabled until
//  each test itself performs and verifies its named lifecycle. A focused
//  hosted harness does not close a different client-side acceptance criterion.
//

import Testing
@testable import AstraStyle

@Suite("Pending connected integration requirements (spec §22)")
struct PendingIntegrationRequirementsTests {

    @Test(
        "Auth lifecycle: sign in, session refresh, sign out against a real Supabase project",
        .disabled(
            "Connected lifecycle test not implemented: hosted Auth exists, but this case does not sign in, restore, and sign out a disposable account. A supported Sign in with Apple or email OTP test flow is also needed. Owner: P1-CORE / P2-ONBOARD. Spec §22 Auth lifecycle."
        )
    )
    func authLifecycle() {
        // The disabled reason above describes the pending connected path.
    }

    @Test(
        "Closet upload and sync: capture -> analyze -> save round trip against live Storage + Postgrest",
        .disabled(
            "Connected capture round trip not implemented here: closet analysis and Storage are deployed, and scanner coverage exists, but this case does not capture/import, upload, analyze, save, and reload a garment against hosted services. Owner: P3-CLOSET / P3-SCAN. Spec §22 Closet upload and sync."
        )
    )
    func closetUploadAndSync() {
        // The disabled reason above describes the pending connected path.
    }

    // Focused Daily Brief production-path and hosted coverage lives in
    // supabase/functions/daily-brief/production_integration_test.ts and
    // hosted_acceptance.ts. It does not replace an iOS signed-in journey.
    // See docs/acceptance/2026-10-09-daily-brief-live-acceptance.md.

    @Test(
        "Product evaluation against the live products Edge Function",
        .disabled(
            "Focused product acceptance exists: products/live_evaluation_acceptance.ts verifies a seeded duplicate candidate without retailer fetching. This native case still needs to connect pasted-link submission through live extraction/evaluation and verify the result in the signed-in app. Owner: P6-SHOP. Spec §22 Product evaluation."
        )
    )
    func productEvaluation() {
        // The disabled reason above describes the pending connected path.
    }

    @Test(
        "Style Studio job polling against live generation and status routes",
        .disabled(
            "Focused hosted Studio generation/polling acceptance exists, including a real provider result. This native case remains open until it verifies the signed-in app request, polling, and rendered result against hosted services; provider spend needs an approved test budget. Owner: P6-STUDIO. Spec §22 Studio job polling."
        )
    )
    func studioJobPolling() {
        // The disabled reason above describes the pending connected path.
    }

    @Test(
        "StoreKit sandbox purchase and server-side reconciliation",
        .disabled(
            "Local paywall/restore UI and subscription sync exist, but a sandbox purchase, renewal/cancel, and restore reconciliation has not been recorded. Requires an App Store Connect sandbox tester and configured products. Owner: P7-SUB / P7-TEST-03. Spec §22 StoreKit sandbox purchase."
        )
    )
    func storeKitSandboxPurchase() {
        // The disabled reason above describes the pending external acceptance.
    }

    @Test(
        "Snapshot tests: major screens in light/dark mode across Dynamic Type sizes",
        .disabled(
            "Not implemented: no snapshot-testing library or baseline suite is wired into the native test target. Spec §22 Snapshot tests."
        )
    )
    func snapshotTestsNotYetConfigured() {
        // The disabled reason above describes the missing snapshot suite.
    }

    @Test(
        "Account deletion end-to-end through completed deletion and account cleanup",
        .disabled(
            "Focused hosted deletion acceptance exists in disposable-account harnesses, including completed receipts and owner cleanup. This native case remains open until one disposable app session signs in, deletes through the UI, verifies receipt/data removal, and signs in again to prove prior data is not restored. Owner: P7-PRIVACY-01/02 / P7-TEST-06. Spec §22 Account deletion."
        )
    )
    func accountDeletionEndToEnd() {
        // The disabled reason above describes the pending connected path.
    }

    @Test(
        "Personal data export: user-scoped data from major user-owned tables",
        .disabled(
            "Hosted export acceptance is complete for populated owner/peer fixtures: see docs/acceptance/2026-10-09-populated-personal-data-export.md and docs/acceptance/2026-10-09-daily-brief-live-acceptance.md. This native test remains open until the app invokes export, presents/shares the file, and verifies the decoded response through the client path. The manifest lists referenced storage paths, not image bytes or proof every object exists. Owner: P7-PRIVACY-03. Spec §§22 and 29."
        )
    )
    func personalDataExportEndToEnd() {
        // The disabled reason above describes the pending native client path.
    }
}
