//
//  AstraEndpoint.swift
//  AstraStyle
//
//  Typed enumeration of every Supabase Edge Function the client is allowed
//  to call (spec §14 "API / Edge Functions" — 16 endpoints, verbatim). The
//  iOS client talks only to these Edge Functions and never directly to a
//  model provider (spec §8).
//

import Foundation

public enum AstraEndpoint: Sendable, Equatable {
    case completeOnboarding
    case generateStyleDNA
    case analyzeClosetItem
    case batchAnalyzeCloset
    /// Poll endpoint for `batchAnalyzeCloset` jobs (HANDOFF §9.3 — batch is
    /// job+poll, never an in-request fan-out on the shared `closet` isolate).
    case batchAnalyzeClosetStatus(id: UUID)
    case generateOutfits
    case rankOutfits
    case generateDailyBrief
    case kyraRespond
    case extractProduct
    case evaluateProduct
    /// Discover Unlocks: HIS evaluated gaps, not a catalog dump.
    case listProductUnlocks
    case generateStudio
    case studioStatus(id: UUID)
    case generatePacking
    case syncSubscriptions
    case appStoreWebhook
    case deleteAccount
    /// Wear This — entitlement lives on the server (ADR 0020).
    case recordWear

    /// HTTP method for the endpoint.
    public var method: HTTPMethod {
        switch self {
        case .studioStatus, .batchAnalyzeClosetStatus:
            .get
        case .deleteAccount:
            .delete
        default:
            .post
        }
    }

    /// Path relative to the Edge Functions base URL
    /// (`{SUPABASE_URL}/functions/v1/`).
    public var path: String {
        switch self {
        case .completeOnboarding: "profile/complete-onboarding"
        case .generateStyleDNA: "style-dna/generate"
        case .analyzeClosetItem: "closet/analyze-item"
        case .batchAnalyzeCloset: "closet/batch-analyze"
        case .batchAnalyzeClosetStatus(let id): "closet/batch-status/\(id.uuidString.lowercased())"
        case .generateOutfits: "outfits/generate"
        case .rankOutfits: "outfits/rank"
        case .generateDailyBrief: "daily-brief/generate"
        case .kyraRespond: "kyra/respond"
        case .extractProduct: "products/extract"
        case .evaluateProduct: "products/evaluate"
        case .listProductUnlocks: "products/unlocks"
        case .generateStudio: "studio/generate"
        case .studioStatus(let id): "studio/status/\(id.uuidString)"
        case .generatePacking: "packing/generate"
        case .syncSubscriptions: "subscriptions/sync"
        case .appStoreWebhook: "app-store/webhook"
        case .deleteAccount: "account"
        case .recordWear: "outfits/record-wear"
        }
    }

    /// Every endpoint requires a valid JWT except the App Store server
    /// notification webhook, which authenticates via its own shared secret
    /// (spec §14 "Validate JWT" applies to user-initiated calls).
    public var requiresAuthentication: Bool {
        self != .appStoreWebhook
    }

    /// Paid / quota-bearing calls must send a stable `Idempotency-Key` so a
    /// mobile retry cannot double-charge (docs/08 §0.1, HANDOFF §9.2).
    public var requiresIdempotencyKey: Bool {
        switch self {
        case .analyzeClosetItem, .batchAnalyzeCloset, .generateStudio:
            true
        default:
            false
        }
    }

    /// Per-endpoint retry policy. Vision analysis may retry 5xx only because
    /// the matching Edge Function is idempotent under `Idempotency-Key`;
    /// endpoints without that guarantee stay on the conservative default.
    public var retryPolicy: AstraRetryPolicy {
        switch self {
        case .analyzeClosetItem:
            // Same attempt budget as `.default`, but named so a future
            // tightening of the vision budget is a one-line change here
            // rather than a silent share with unrelated endpoints.
            .paidProvider
        case .batchAnalyzeCloset, .batchAnalyzeClosetStatus:
            // Enqueue/poll are cheap; status polls are frequent and should
            // not stampede the isolate after a blip.
            .batchJob
        default:
            .default
        }
    }
}

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}
