//
//  EndpointDeploymentMappingTests.swift
//  AstraStyleTests
//
//  Guards the mapping between `AstraEndpoint.path` and what is actually
//  deployable on Supabase. Supabase routes `/functions/v1/{slug}/{rest}`
//  by the FIRST path segment only — the deployed function's slug — so a
//  client path whose first segment has no matching function directory under
//  `supabase/functions/` 404s in production while every unit test stays
//  green. That is not hypothetical: the vertical slice shipped calling
//  `POST /outfits/generate` while the only deployed function was named
//  `outfits-generate`, so every production call 404'd
//  (docs/adr/0013-edge-function-routing.md). These tests exist to make that
//  class of bug fail in CI instead of at runtime.
//
//  HOW TO UPDATE when adding an Edge Function or endpoint:
//   1. Name the new function directory under `supabase/functions/` after
//      the FIRST path segment of the spec §14 endpoint(s) it serves
//      (e.g. `closet/` for `closet/analyze-item` + `closet/batch-analyze`),
//      routing internally via `_shared/routing.ts`.
//   2. If that first segment is genuinely new (i.e. spec §14 grew), add it
//      to `expectedSlugs` below. Do NOT add a slug that no endpoint path
//      uses — the consistency test below fails on orphans in either
//      direction, so the list can't silently rot.
//   3. Add the new `AstraEndpoint` case to `allEndpoints` below — the
//      exhaustive switch in `assertCovered(_:)` fails to compile until you
//      do, so forgetting is impossible rather than merely unlikely.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Endpoint-to-Edge-Function deployment mapping")
struct EndpointDeploymentMappingTests {

    /// The deployed Edge Function slugs — one per distinct first path
    /// segment across spec §14's 16 endpoints. This is the deployment
    /// contract: every one of these must exist (now or when its phase
    /// ships) as a directory under `supabase/functions/`.
    private static let expectedSlugs: Set<String> = [
        "outfits",
        "profile",
        "style-dna",
        "closet",
        "daily-brief",
        "kyra",
        "products",
        "studio",
        "packing",
        "subscriptions",
        "app-store",
        "account"
    ]

    /// Every `AstraEndpoint` case. `assertCovered(_:)` below is an
    /// exhaustive switch with no `default`, so adding an enum case without
    /// extending this list is a compile error, not a silent coverage gap.
    private static let allEndpoints: [AstraEndpoint] = [
        .completeOnboarding,
        .generateStyleDNA,
        .analyzeClosetItem,
        .batchAnalyzeCloset,
        .batchAnalyzeClosetStatus(id: UUID()),
        .generateOutfits,
        .rankOutfits,
        .generateDailyBrief,
        .kyraRespond,
        .extractProduct,
        .evaluateProduct,
        .listProductUnlocks,
        .generateStudio,
        .studioStatus(id: UUID()),
        .generatePacking,
        .syncSubscriptions,
        .appStoreWebhook,
        .deleteAccount,
        .recordWear
    ]

    /// Never called at runtime; exists purely so the compiler enforces that
    /// `allEndpoints` was consciously reviewed whenever `AstraEndpoint`
    /// gains a case (the new case makes this switch non-exhaustive).
    private static func assertCovered(_ endpoint: AstraEndpoint) {
        switch endpoint {
        case .completeOnboarding, .generateStyleDNA, .analyzeClosetItem,
             .batchAnalyzeCloset, .batchAnalyzeClosetStatus, .generateOutfits, .rankOutfits,
             .generateDailyBrief, .kyraRespond, .extractProduct,
             .evaluateProduct, .listProductUnlocks, .generateStudio, .studioStatus,
             .generatePacking, .syncSubscriptions, .appStoreWebhook,
             .deleteAccount, .recordWear:
            break
        }
    }

    private static func firstSegment(of endpoint: AstraEndpoint) -> String? {
        endpoint.path.split(separator: "/").first.map(String.init)
    }

    @Test("Every endpoint's first path segment is a deployed function slug")
    func everyEndpointRoutesToADeployedSlug() {
        for endpoint in Self.allEndpoints {
            guard let slug = Self.firstSegment(of: endpoint) else {
                Issue.record("Endpoint \(endpoint) has an empty path — it cannot route to any Edge Function.")
                continue
            }
            #expect(
                Self.expectedSlugs.contains(slug),
                "Endpoint path '\(endpoint.path)' begins with '\(slug)', which is not a known Edge Function slug. Supabase routes by first path segment only, so this call would 404 in production. See this file's header for how to add a slug."
            )
        }
    }

    @Test("The slug list and the endpoint paths agree exactly, in both directions")
    func slugListHasNoOrphans() {
        let derived = Set(Self.allEndpoints.compactMap(Self.firstSegment(of:)))
        #expect(
            derived == Self.expectedSlugs,
            "expectedSlugs and the first segments of every AstraEndpoint.path must be the same set. Only in endpoints (missing from expectedSlugs): \(derived.subtracting(Self.expectedSlugs).sorted()). Only in expectedSlugs (no endpoint uses them): \(Self.expectedSlugs.subtracting(derived).sorted())."
        )
    }

    // Cross-check against the actual `supabase/functions/` directory, found
    // relative to this source file via `#filePath`. Unit tests run in the
    // simulator, which shares the host filesystem, so the checkout is
    // readable; if this ever runs somewhere the sources genuinely aren't
    // (it shouldn't — tests build from the checkout), the explicit
    // Issue.record below makes that a loud failure to investigate, not a
    // silently skipped check.
    @Test("Every function directory under supabase/functions/ is a slug some endpoint uses")
    func deployedFunctionDirectoriesMatchClientSlugs() throws {
        let functionsDir = URL(fileURLWithPath: #filePath)     // .../ios/AstraStyle/Tests/UnitTests/EndpointDeploymentMappingTests.swift
            .deletingLastPathComponent()                        // .../ios/AstraStyle/Tests/UnitTests
            .deletingLastPathComponent()                        // .../ios/AstraStyle/Tests
            .deletingLastPathComponent()                        // .../ios/AstraStyle
            .deletingLastPathComponent()                        // .../ios
            .deletingLastPathComponent()                        // repo root
            .appendingPathComponent("supabase/functions", isDirectory: true)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: functionsDir.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            Issue.record("supabase/functions/ not found at \(functionsDir.path) — the deployment cross-check could not run. If the repo layout moved, update the path derivation in this test.")
            return
        }

        let entries = try FileManager.default.contentsOfDirectory(
            at: functionsDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        let functionDirectories = entries.filter { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            // `_shared/` is a library the functions import, not a
            // deployable function — the Supabase CLI skips underscore-
            // prefixed directories, and so does this check.
            return isDir && !url.lastPathComponent.hasPrefix("_")
        }.map(\.lastPathComponent)

        // Direction 1: no function directory the client can't reach. A
        // directory named outside the slug list (like the original
        // `outfits-generate`) deploys fine but serves URLs no
        // `AstraEndpoint` ever builds.
        for directory in functionDirectories {
            #expect(
                Self.expectedSlugs.contains(directory),
                "supabase/functions/\(directory)/ is not a slug any AstraEndpoint path starts with — the client cannot reach it. Function directories must be named after the first path segment of the spec §14 endpoints they serve."
            )
        }

        // Direction 2: the functions that are supposed to exist already do.
        // Grow this set as later phases add functions — it should always
        // equal the set of function directories intentionally present.
        // `outfits` shipped with the vertical slice; `profile` and
        // `style-dna` landed with Phase 2 (P2-ONBOARD-12, P2-CORE-02), which
        // is what makes onboarding completable at all.
        //
        // `daily-brief` was added on 2026-08-06 and is the reason this set
        // matters. It sat in `expectedSlugs` but not here for weeks while
        // `HomeBriefProviding` called it on every load, so the one test
        // written to catch exactly this had a hole exactly where the bug
        // was: Home's 404 was invisible to CI. **A slug belongs here the
        // moment a production call path builds a URL for it**, not once
        // someone remembers.
        let requiredNow: Set<String> = [
            "outfits",
            "profile",
            "style-dna",
            "closet",
            "daily-brief",
            "products",
            "studio",
            "subscriptions",
            "packing"
        ]
        for slug in requiredNow {
            #expect(
                functionDirectories.contains(slug),
                "supabase/functions/\(slug)/ is missing, but the client builds URLs whose first segment is '\(slug)'. Those calls 404 in production without it."
            )
        }
    }

    @Test("Paid closet analysis endpoints require an Idempotency-Key and use a non-default retry policy")
    func closetAnalysisRetryAndIdempotencyContract() {
        #expect(AstraEndpoint.analyzeClosetItem.requiresIdempotencyKey)
        #expect(AstraEndpoint.batchAnalyzeCloset.requiresIdempotencyKey)
        #expect(!AstraEndpoint.batchAnalyzeClosetStatus(id: UUID()).requiresIdempotencyKey)
        #expect(AstraEndpoint.analyzeClosetItem.retryPolicy == .paidProvider)
        #expect(AstraEndpoint.batchAnalyzeCloset.retryPolicy == .batchJob)
        #expect(AstraEndpoint.batchAnalyzeClosetStatus(id: UUID()).method == .get)
        #expect(AstraEndpoint.batchAnalyzeClosetStatus(id: UUID()).path.hasPrefix("closet/batch-status/"))
    }
}
